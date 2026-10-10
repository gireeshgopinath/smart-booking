[CmdletBinding()]
param()

# Inventory is one T01 criterion, never parent acceptance. No tool installation,
# model request, Git initialization, or external staging pointer is performed.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')).TrimEnd([char[]]'\/')
$started = [DateTime]::UtcNow.ToString('o')
$runId = 'inventory-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
$problems = [Collections.Generic.List[string]]::new()

function Resolve-SafePath([string]$relative) {
    if ([IO.Path]::IsPathRooted($relative)) { throw 'Absolute input path rejected.' }
    $full = [IO.Path]::GetFullPath((Join-Path $root $relative))
    if (-not $full.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Path escapes workspace.' }
    $cursor = $full
    while ($cursor.Length -ge $root.Length) {
        if ((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Reparse point in input/output path.' }
        if ($cursor -eq $root) { break }
        $cursor = Split-Path -Parent $cursor
    }
    return $full
}

function Get-Digest([string]$text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [Convert]::ToHexString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))).ToLowerInvariant() } finally { $sha.Dispose() }
}

function Test-CredentialPath([string]$path) {
    return ($path -match '(?i)(^|/)(\.env($|\.)|credentials?([./]|$)|secrets?([./]|$)|id_rsa|id_ed25519|[^/]+\.(pem|key|pfx|p12|jks|keystore)$)' -and $path -notmatch '(?i)\.env\.(example|sample|template)$')
}

function Get-Category([string]$path) {
    if ($path -in @('Booking_Application_Master_Execution_Plan.md','Booking_Backend_Local_Agent_Execution_Plan.md','Booking_Application_Design_and_Development.docx')) { return 'supplied-design' }
    if ($path -eq 'docs/verification/VERIFICATION_MATRIX.md') { return 'preparation-artifact' }
    if ($path -eq '.t01-neg-exits.json' -or $path -match '(^|/)(target|build|dist|node_modules|\.tools|\.git)(/|$)|^docs/(execution/(runs|prepared|packets)|verification)/') { return 'generated-output' }
    if ($path -match '^modules/|^\.mvn/|^(pom\.xml|mvnw|mvnw\.cmd|\.editorconfig|\.gitignore)$') { return 'unreviewed-scaffold' }
    return 'preparation-artifact'
}

function Get-Inventory([switch]$SourceOnly) {
    $files = [Collections.Generic.List[object]]::new()
    $omissions = [Collections.Generic.List[object]]::new()
    $queue = [Collections.Generic.Queue[string]]::new()
    $queue.Enqueue($root)
    while ($queue.Count) {
        foreach ($item in @(Get-ChildItem -LiteralPath $queue.Dequeue() -Force)) {
            $relative = $item.FullName.Substring($root.Length + 1).Replace('\','/')
            $category = Get-Category $(if ($item.PSIsContainer) { $relative + '/' } else { $relative })
            # The verification matrix is a specification, so traverse its parent
            # directory even when omitting the generated task evidence below it.
            if ($SourceOnly -and $category -eq 'generated-output' -and -not ($item.PSIsContainer -and $relative -eq 'docs/verification')) { continue }
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                $omissions.Add([ordered]@{path=$relative; reason='reparse-point-not-followed'; category=$category})
                # Historical controller test fixtures contain intentional junctions.
                # Record them without following them; source junctions fail inventory.
                if ($category -ne 'generated-output') { $problems.Add('Source inventory contains a reparse point: ' + $relative) }
                continue
            }
            if ($item.PSIsContainer) {
                # Never traverse global/dependency caches, Git objects or this verifier's outputs.
                if ($item.Name -in @('.git','.tools','.m2','.gradle','node_modules','target','build','dist','.venv','venv','__pycache__') -or $relative -match '^docs/verification/T01/(independent|inventory-runs)(/|$)') {
                    $omissions.Add([ordered]@{path=$relative;reason='generated-directory-not-traversed';category='generated-output'})
                } else { $queue.Enqueue($item.FullName) }
                continue
            }
            if (Test-CredentialPath $relative) {
                $omissions.Add([ordered]@{path=$relative;reason='credential-path-content-not-read';category=$category})
                continue
            }
            # Live private controller transcripts/locks are inventoried by metadata.
            # Their bytes are not a source input and may be actively written/locked.
            $hash = if ($relative -match '^docs/execution/runs/') { $null } else { (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
            $files.Add([ordered]@{path=$relative;bytes=$item.Length;sha256=$hash;category=$category})
        }
    }
    return [pscustomobject]@{files=@($files | Sort-Object { $_.path }); omissions=$omissions.ToArray()}
}

function Get-SourceFingerprint($inventory) {
    $files = @($inventory.files | Where-Object { $_.category -ne 'generated-output' })
    $basis = ($files | ForEach-Object { $_.path + ':' + $_.sha256 }) -join "`n"
    return [ordered]@{revision=('no-git-sha256:' + (Get-Digest $basis)); algorithm='UTF-8 sorted relative-path:SHA256 lines, LF separators, no terminal LF';files=$files; exclusions=@('generated outputs/caches','credential paths','reparse points')}
}

function Invoke-Probe([string]$executable, [string[]]$arguments) {
    $probeStart = [DateTime]::UtcNow.ToString('o')
    $command = Get-Command $executable -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) { return [ordered]@{command=$executable;arguments=$arguments;startedAtUtc=$probeStart;endedAtUtc=[DateTime]::UtcNow.ToString('o');exitCode=$null;state='MISSING';output='Executable not found on PATH.'} }
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $command.Source
    $info.WorkingDirectory = $root
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    # JVM launchers echo these values (which can contain credentials) to stderr.
    # Remove them only from the child diagnostic process, never machine/session state.
    if ($executable -in @('java','javac')) {
        foreach ($name in @('JAVA_TOOL_OPTIONS','JDK_JAVA_OPTIONS','_JAVA_OPTIONS')) { [void]$info.Environment.Remove($name) }
    }
    foreach ($argument in $arguments) { $info.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(10000)) {
            $process.Kill($true)
            $process.WaitForExit()
            $state = 'TIMEOUT'
        } else { $state = if ($process.ExitCode -eq 0) { 'SUCCEEDED' } else { 'FAILED' } }
        $output = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
        $output = $output -replace '(?i)(Bearer\s+)[^\s]+','$1[REDACTED]' -replace '(https?://)[^\s/@]+:[^\s/@]+@','$1[REDACTED]@'
        return [ordered]@{command=$executable;arguments=$arguments;resolvedExecutable=$command.Source;startedAtUtc=$probeStart;endedAtUtc=[DateTime]::UtcNow.ToString('o');exitCode=$process.ExitCode;state=$state;output=$output}
    } catch {
        return [ordered]@{command=$executable;arguments=$arguments;startedAtUtc=$probeStart;endedAtUtc=[DateTime]::UtcNow.ToString('o');exitCode=$null;state='UNAVAILABLE';output=$_.Exception.GetType().FullName}
    } finally { $process.Dispose() }
}

function Get-TaskHeadings([string]$relative) {
    $text = [IO.File]::ReadAllText((Resolve-SafePath $relative))
    return @([regex]::Matches($text, '(?m)^###\s+(T\d{2})\s+(?:—\s+)?(.+?)\r?$') | ForEach-Object { [ordered]@{id=$_.Groups[1].Value;title=$_.Groups[2].Value.Trim()} })
}

function Write-Evidence([string]$name, $data) {
    $payload = [ordered]@{schemaVersion=1;taskId='T01';slice='S01';runId=$runId;startedAtUtc=$started;finishedAtUtc=[DateTime]::UtcNow.ToString('o');command='pwsh -NoProfile -File scripts/verify/verify-T01-inventory.ps1';sourceFingerprint=$fingerprint.revision;environment=[ordered]@{powershell=$PSVersionTable.PSVersion.ToString();os=[Runtime.InteropServices.RuntimeInformation]::OSDescription;workspace=$root};data=$data}
    $json = ($payload | ConvertTo-Json -Depth 40) + "`n"
    foreach ($directory in @($runDirectory, $independent)) { [IO.File]::WriteAllText((Resolve-SafePath ($directory + '/' + $name)), $json, [Text.UTF8Encoding]::new($false)) }
}

$independent = 'docs/verification/T01/independent'
$runDirectory = 'docs/verification/T01/inventory-runs/' + $runId
$fingerprint = [ordered]@{revision=$null}
try {
    [void](Resolve-SafePath 'scripts/verify/verify-T01-inventory.ps1')
    if (Test-Path -LiteralPath (Resolve-SafePath $runDirectory)) { throw 'Unique run directory already exists.' }
    [void][IO.Directory]::CreateDirectory((Resolve-SafePath $runDirectory))
    [void][IO.Directory]::CreateDirectory((Resolve-SafePath $independent))
    $names = @('inventory.json','reconciliation.json','source-preservation.json','boundary-audit.json','tool-diagnostics.json','inventory-result.json')
    # Archive only the files owned by this verifier; other verifier evidence is untouched.
    foreach ($name in $names) {
        $prior = Resolve-SafePath ($independent + '/' + $name)
        if (Test-Path -LiteralPath $prior) {
            [void][IO.Directory]::CreateDirectory((Resolve-SafePath ($runDirectory + '/prior')))
            Copy-Item -LiteralPath $prior -Destination (Resolve-SafePath ($runDirectory + '/prior/' + $name))
        }
    }
    $inventory = Get-Inventory
    $fingerprint = Get-SourceFingerprint $inventory
    $initialFiles = @{}; foreach ($file in $inventory.files) { $initialFiles[$file.path] = $file }
    $manifest = Get-Content -LiteralPath (Resolve-SafePath 'docs/sources/source-manifest.json') -Raw | ConvertFrom-Json
    $preservation = @($manifest.sources | ForEach-Object {
        $path = Resolve-SafePath $_.path
        $bytes = (Get-Item -LiteralPath $path).Length
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        $matches = $bytes -eq $_.bytes -and $hash -ceq $_.sha256
        if (-not $matches) { $problems.Add('Supplied document changed: ' + $_.path) }
        [ordered]@{path=$_.path;expectedBytes=$_.bytes;actualBytes=$bytes;expectedSha256=$_.sha256;actualSha256=$hash;matches=$matches}
    })
    if ($preservation.Count -ne 3) { $problems.Add('Source manifest must contain exactly three supplied documents.') }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $docx = [IO.Compression.ZipFile]::OpenRead((Resolve-SafePath 'Booking_Application_Design_and_Development.docx'))
    try {
        $entry = $docx.GetEntry('word/document.xml')
        if (-not $entry) { throw 'DOCX document XML is missing.' }
        $reader = [IO.StreamReader]::new($entry.Open())
        try { [xml]$xml = $reader.ReadToEnd() } finally { $reader.Dispose() }
        $ns = [Xml.XmlNamespaceManager]::new($xml.NameTable)
        $ns.AddNamespace('w','http://schemas.openxmlformats.org/wordprocessingml/2006/main')
        $paragraphs = @($xml.SelectNodes('//w:body/w:p', $ns) | ForEach-Object { ($_.SelectNodes('.//w:t', $ns) | ForEach-Object InnerText) -join '' })
        $tables = @($xml.SelectNodes('//w:body/w:tbl', $ns) | ForEach-Object {
            $rows = @($_.SelectNodes('./w:tr', $ns) | ForEach-Object {
                $cells = @($_.SelectNodes('./w:tc', $ns) | ForEach-Object { ($_.SelectNodes('.//w:t', $ns) | ForEach-Object InnerText) -join '' })
                [ordered]@{cells=$cells}
            })
            [ordered]@{rows=$rows}
        })
        if ($paragraphs.Count -eq 0) { throw 'DOCX paragraph extraction returned no content.' }
    } finally { $docx.Dispose() }
    $master = Get-TaskHeadings 'Booking_Application_Master_Execution_Plan.md'
    $backend = Get-TaskHeadings 'Booking_Backend_Local_Agent_Execution_Plan.md'
    $tasks = (Get-Content -LiteralPath (Resolve-SafePath 'contracts/tasks.json') -Raw | ConvertFrom-Json).tasks
    $expected = @(1..42 | ForEach-Object { 'T{0:D2}' -f $_ })
    foreach ($comparison in @(@{name='Master';actual=@($master.id);expected=$expected},@{name='Backend';actual=@($backend.id);expected=@($expected[0..25])},@{name='Task index';actual=@($tasks.id);expected=$expected})) {
        if (@(Compare-Object $comparison.expected $comparison.actual).Count -or @($comparison.actual | Select-Object -Unique).Count -ne $comparison.expected.Count) { $problems.Add($comparison.name + ' task identifiers do not reconcile.') }
    }
    $packetRows = @($tasks | ForEach-Object {
        $packet = Resolve-SafePath $_.specPath
        $matches = (Test-Path -LiteralPath $packet -PathType Leaf) -and ([IO.File]::ReadAllText($packet) -match ('(?m)^# ' + [regex]::Escape($_.id) + ' — ' + [regex]::Escape($_.title) + '\r?$'))
        $masterRow = @($master | Where-Object id -eq $_.id)
        if ($masterRow.Count -ne 1 -or $masterRow[0].title -cne $_.title -or -not $matches) { $problems.Add('Task title/packet mismatch: ' + $_.id) }
        [ordered]@{id=$_.id;title=$_.title;packet=$_.specPath;packetHeadingMatches=$matches}
    })
    foreach ($row in $backend) {
        $masterRow = @($master | Where-Object id -eq $row.id)
        if ($masterRow.Count -ne 1 -or $masterRow[0].title -cne $row.title) { $problems.Add('Retained backend task title mismatch: ' + $row.id) }
    }
    # These are explicitly adopted replacements, not recovered source documents.
    $replacementDefinitions = @(
        @('00_START_HERE.md','README.md'),
        @('product specification','docs/DEVELOPMENT_GOAL.md'),
        @('architecture specification','docs/architecture/SYSTEM_DESIGN.md'),
        @('data specification','docs/architecture/DOMAIN_CONTRACT.md'),
        @('AI specification','docs/architecture/BLUEPRINT_CONTRACT.md'),
        @('08_MASTER_EXECUTION_PLAN.md','Booking_Application_Master_Execution_Plan.md'),
        @('09_LOCAL_AI_AND_CHATGPT_GUIDE.md','docs/LOCAL_AI_AND_CODEX_GUIDE.md'),
        @('10_VERIFICATION_AND_TRACEABILITY.md','docs/verification/VERIFICATION_MATRIX.md'),
        @('review templates','docs/execution/templates/review-packet.md'),
        @('starter blueprint schema','contracts/booking-blueprint.schema.json'),
        @('synthetic salon template','examples/salon.blueprint.json'),
        @('twelve original ADRs','docs/architecture/adr/README.md')
    )
    $replacements = @($replacementDefinitions | ForEach-Object {
        $exists = Test-Path -LiteralPath (Resolve-SafePath $_[1]) -PathType Leaf
        if (-not $exists) { $problems.Add('Missing adopted replacement: ' + $_[1]) }
        [ordered]@{referencedSupport=$_[0];replacement=$_[1];exists=$exists;provenance='adopted replacement documented in docs/PLAN_ANALYSIS.md; not originally supplied'}
    })
    $probes = @(Invoke-Probe 'git' @('status','--short'); Invoke-Probe 'git' @('rev-parse','--verify','HEAD'); Invoke-Probe 'java' @('-version'); Invoke-Probe 'javac' @('-version'); Invoke-Probe 'mvn' @('--version'); Invoke-Probe 'docker' @('version'); Invoke-Probe 'node' @('--version'); Invoke-Probe 'python' @('--version'))
    $ports = @(5432,6379,8080,7233,4566,1025,8025,1234,11434 | ForEach-Object {
        $client = [Net.Sockets.TcpClient]::new()
        try { $connect = $client.ConnectAsync('127.0.0.1', $_); $listening = $connect.Wait(1000) -and $client.Connected; $state = if ($listening) { 'LISTENING' } else { 'TIMEOUT_OR_NOT_LISTENING' } } catch { $state = 'NOT_REACHABLE' } finally { $client.Dispose() }
        [ordered]@{address='127.0.0.1';port=$_;state=$state;observation='TCP only; no health/inference/identity claim'}
    })
    try { $services = @(Get-Service -Name '*docker*','*ollama*','*lmstudio*' -ErrorAction Stop | Select-Object Name,Status); $serviceState = 'OBSERVED' } catch { $services = @(); $serviceState = 'UNAVAILABLE_OR_NO_MATCHING_SERVICE' }

    # Manual Start captures the current preserved starting state before launch.
    # Older automatic captures remain historical, not the current write boundary.
    $controllerSnapshot = $null
    $manualCandidates = @(Get-ChildItem -LiteralPath (Resolve-SafePath 'docs/execution/runs') -Directory -Filter 'manual-T01-start-*' | Sort-Object Name -Descending | ForEach-Object {
        $relative = $_.FullName.Substring($root.Length + 1).Replace('\','/')
        $capture = Resolve-SafePath ($relative + '/before-source.json')
        if (Test-Path -LiteralPath $capture -PathType Leaf) { $capture }
    })
    if ($manualCandidates.Count) { $controllerSnapshot = $manualCandidates[0].Substring($root.Length + 1).Replace('\','/') }
    $statePath = Resolve-SafePath 'docs/execution/runs/automatic/state.json'
    if (-not $controllerSnapshot -and (Test-Path -LiteralPath $statePath)) {
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        $campaign = Resolve-SafePath ($state.campaignDirectory + '/T01')
        $candidates = @(Get-ChildItem -LiteralPath $campaign -Directory | Where-Object Name -match '^(session-\d+|plan-\d+)$' | ForEach-Object {
            $candidateRelative = $_.FullName.Substring($root.Length + 1).Replace('\','/')
            $candidateDirectory = Resolve-SafePath $candidateRelative
            Get-ChildItem -LiteralPath $candidateDirectory -File -Filter before-source.json
            $implementationCapture = Resolve-SafePath ($candidateRelative + '/implementation/before-source.json')
            if (Test-Path -LiteralPath $implementationCapture) { Get-Item -LiteralPath $implementationCapture }
        } | Sort-Object LastWriteTimeUtc -Descending)
        if ($candidates.Count) { $controllerSnapshot = $candidates[0].FullName.Substring($root.Length + 1).Replace('\','/') }
    }
    $boundary = [Collections.Generic.List[object]]::new()
    $supplementalSnapshot = $null
    $supplementalFiles = @()
    if (-not $controllerSnapshot) { $problems.Add('Controller-captured starting snapshot unavailable; preservation cannot be asserted.') } else {
        $before = Get-Content -LiteralPath (Resolve-SafePath $controllerSnapshot) -Raw | ConvertFrom-Json
        $allowed = '^(\.editorconfig|\.gitignore|mvnw|mvnw\.cmd|pom\.xml)$|^\.mvn/|^modules/(api-contracts|domain)/|^docs/adr/T01-toolchain-baseline\.md$|^docs/execution/(dependency-manifest\.json|repository-assessment\.md|review-packets/T01\.md)$|^docs/verification/T01/|^scripts/verify/verify-T01(-inventory|-compatibility|-secrets)?\.ps1$'
        $known = @{}
        foreach ($file in $before.files) {
            $known[$file.path] = $true
            # Only mutable outputs of these verifiers can change during independent checks.
            if ($file.path -match '^docs/verification/T01/(independent|inventory-runs)/') { continue }
            $unchanged = $initialFiles.ContainsKey($file.path) -and $initialFiles[$file.path].sha256 -ceq $file.sha256
            $permitted = $file.path -match $allowed
            $boundary.Add([ordered]@{path=$file.path;unchanged=$unchanged;allowedT01Path=$permitted;expectedSha256=$file.sha256;actualSha256=$(if ($initialFiles.ContainsKey($file.path)) { $initialFiles[$file.path].sha256 } else { $null })})
            if (-not $unchanged -and (-not $permitted -or $file.path -match '^docs/verification/T01/(session-001/|negatives/|spotless-apply\.log$|wrapper-verify\.log$)')) { $problems.Add('Unrelated or historical starting file changed: ' + $file.path) }
        }
        foreach ($file in $inventory.files | Where-Object { $_.category -ne 'generated-output' }) {
            if (-not $known.ContainsKey($file.path) -and $file.path -notmatch $allowed) { $problems.Add('Unrelated source added: ' + $file.path) }
        }
        # Preserve generated artifacts created after the planner's snapshot but
        # already present at implementation start. This is labelled implementer
        # capture and cannot excuse any unrelated source addition or edit.
        $taskEvidence = Resolve-SafePath 'docs/verification/T01'
        $supplementalCandidates = @(Get-ChildItem -LiteralPath $taskEvidence -Directory -Filter 'session-s01-*' | ForEach-Object {
            $capture = Resolve-SafePath ($_.FullName.Substring($root.Length + 1).Replace('\','/') + '/before-source.json')
            if (Test-Path -LiteralPath $capture) { Get-Item -LiteralPath $capture }
        } | Sort-Object FullName -Descending)
        if (-not $manualCandidates.Count -and $supplementalCandidates.Count) {
            $supplementalSnapshot = $supplementalCandidates[0].FullName.Substring($root.Length + 1).Replace('\','/')
            $capture = Get-Content -LiteralPath (Resolve-SafePath $supplementalSnapshot) -Raw | ConvertFrom-Json
            $supplementalFiles = @($capture.files | Where-Object { -not $known.ContainsKey($_.path) -and (Get-Category $_.path) -eq 'generated-output' })
            foreach ($file in $supplementalFiles) {
                $unchanged = $initialFiles.ContainsKey($file.path) -and $initialFiles[$file.path].sha256 -ceq $file.sha256
                $boundary.Add([ordered]@{path=$file.path;unchanged=$unchanged;allowedT01Path=$false;basis='supplemental implementer-start capture';expectedSha256=$file.sha256;actualSha256=$(if ($initialFiles.ContainsKey($file.path)) { $initialFiles[$file.path].sha256 } else { $null })})
                if (-not $unchanged) { $problems.Add('Preexisting generated artifact changed: ' + $file.path) }
            }
        }
    }
    # Rehash all observed inputs after work; outputs are outside the fingerprint.
    foreach ($file in $fingerprint.files) {
        if ((Get-FileHash -LiteralPath (Resolve-SafePath $file.path) -Algorithm SHA256).Hash.ToLowerInvariant() -cne $file.sha256) { $problems.Add('Source changed during verification: ' + $file.path) }
    }
    $finalFingerprint = Get-SourceFingerprint (Get-Inventory -SourceOnly)
    if ($finalFingerprint.revision -cne $fingerprint.revision) { $problems.Add('Source file set changed during verification.') }
    foreach ($file in $supplementalFiles) {
        if ((Get-FileHash -LiteralPath (Resolve-SafePath $file.path) -Algorithm SHA256).Hash.ToLowerInvariant() -cne $file.sha256) { $problems.Add('Preexisting generated artifact changed during verification: ' + $file.path) }
    }
    Write-Evidence 'inventory.json' ([ordered]@{files=$inventory.files;omissions=$inventory.omissions;counts=@($inventory.files | Group-Object { $_.category } | Select-Object Name,Count);source=$fingerprint;stagingPointers='Metadata inventoried as files only; no external path followed.';privateRunCoverage='Private controller run files have metadata only, with null SHA256; their bytes and live locks are not source inputs.'})
    Write-Evidence 'reconciliation.json' ([ordered]@{masterTasks=$master;backendTasks=$backend;packets=$packetRows;adoptedReplacements=$replacements;provenanceAuthority='docs/PLAN_ANALYSIS.md';docx=[ordered]@{method='word/document.xml directly from OOXML ZIP, top-level paragraphs and table rows/cells';paragraphs=$paragraphs;tables=$tables};unrecoveredDefinitions=@('original R01-R30 definitions','original twelve ADR contents');problems=$problems.ToArray()})
    Write-Evidence 'source-preservation.json' ([ordered]@{manifest='docs/sources/source-manifest.json';manifestSha256=(Get-FileHash -LiteralPath (Resolve-SafePath 'docs/sources/source-manifest.json') -Algorithm SHA256).Hash.ToLowerInvariant();suppliedDocuments=$preservation;allMatch=(@($preservation | Where-Object { -not $_.matches }).Count -eq 0)})
    Write-Evidence 'boundary-audit.json' ([ordered]@{startingSnapshot=$controllerSnapshot;supplementalImplementerSnapshot=$supplementalSnapshot;comparisons=$boundary.ToArray();problems=$problems.ToArray();scope='Controller snapshot plus labelled implementer-start coverage of additional generated artifacts; credentials, caches, private runs and mutable progress excluded by controller. Historical logs covered by either snapshot are hashed and retained.'})
    Write-Evidence 'tool-diagnostics.json' ([ordered]@{probes=$probes;ports=$ports;services=$services;serviceProbe=$serviceState;limitations='Absent Maven and failed Docker/Git probes are observations, not healthy runtime dependencies. Models are neither enumerated nor invoked.'})
    $code = if ($problems.Count) { 1 } else { 0 }
    Write-Evidence 'inventory-result.json' ([ordered]@{exitCode=$code;passed=($code -eq 0);problems=$problems.ToArray();parentTaskComplete=$false;remainingMandatorySlices=@('S02 official compatibility and checksum','S03 library compatibility tests','S04 clean staging build and negative controls','S05 secret scan','S06 independent verification and separate review')})
    Write-Output ('T01 S01 inventory: exit ' + $code + '; run ' + $runId + '; source ' + $fingerprint.revision)
    exit $code
} catch {
    # Failed collection is never replaced with empty passing evidence.
    $failure = [ordered]@{exitCode=1;passed=$false;errorType=$_.Exception.GetType().FullName;message=$_.Exception.Message;parentTaskComplete=$false}
    if (Test-Path -LiteralPath (Resolve-SafePath $runDirectory)) { Write-Evidence 'inventory-result.json' $failure }
    Write-Error ('T01 inventory failed: ' + $_.Exception.Message) -ErrorAction Continue
    exit 1
}
