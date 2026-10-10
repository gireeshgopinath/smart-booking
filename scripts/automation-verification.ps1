Set-StrictMode -Version 2.0

# This is an independent execution gate, not an approval engine. GPT must still
# review whether each executed check proves the complete feature specification.
if (-not (Get-Command Get-SourceSnapshot -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'workflow-common.ps1')
}

function Resolve-AutomationVerificationPath {
    param([string]$Root, [string]$Path, [switch]$MustExist)
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd([char[]]'\/')
    $full = if ([IO.Path]::IsPathRooted($Path)) { [IO.Path]::GetFullPath($Path) } else { [IO.Path]::GetFullPath((Join-Path $rootPath $Path)) }
    if (-not $full.StartsWith($rootPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "Verification path escapes workspace: $Path" }
    $cursor = $full
    while ($cursor -and $cursor.Length -gt $rootPath.Length) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Verification path contains a reparse point: $Path" }
        }
        $cursor = Split-Path -Parent $cursor
    }
    if ($MustExist -and -not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Missing verification file: $Path" }
    return $full
}

function Get-AutomationVerificationRelativePath {
    param([string]$Root, [string]$Path)
    $full = Resolve-AutomationVerificationPath $Root $Path
    return $full.Substring([IO.Path]::GetFullPath($Root).TrimEnd([char[]]'\/').Length + 1).Replace('\','/')
}

function Get-AutomationVerificationSnapshot {
    param([string]$Root, [string]$TaskId)
    $snapshot = Get-SourceSnapshot $Root
    # Feature verification is permitted to create evidence, never source changes.
    $files = @($snapshot.files | Where-Object { $_.path -notmatch ('^docs/verification/' + [regex]::Escape($TaskId) + '/') })
    foreach ($relative in @('docs/execution/task-ledger.json','docs/execution/task-ledger.md','docs/execution/next-step.md')) {
        $path = Resolve-AutomationVerificationPath $Root $relative
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $files += [pscustomobject]@{path=$relative;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant();bytes=(Get-Item -LiteralPath $path).Length}
        }
    }
    $ordered = @($files | Sort-Object path)
    $basis = ($ordered | ForEach-Object { $_.path + ':' + $_.sha256 }) -join "`n"
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $digest = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($basis))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
    return [pscustomobject]@{revision=('verification-snapshot:' + $digest);workspaceRevision=$snapshot.revision;files=$ordered;exclusions=@($snapshot.exclusions)+@('Current task verification evidence only')}
}

function Test-AutomationVerificationScript {
    param([string]$Path)
    $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if (-not $content.Trim()) { throw "Empty verification script: $Path" }
    $parseErrors = $null; $parseTokens = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($content, [ref]$parseTokens, [ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) { throw "Verification script has syntax errors: $Path" }
    $commands = @($ast.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst]}, $true))
    $substantiveCommands = @($commands | Where-Object {
        $name = $_.GetCommandName()
        # Dynamic invocations are inspected by GPT; reject common output-only stubs.
        $null -eq $name -or $name -notmatch '^(Write-(Host|Output|Information|Verbose|Warning|Debug)|Out-(Null|String)|Set-StrictMode|Start-Sleep)$'
    })
    $assertions = @($ast.FindAll({param($node) $node -is [Management.Automation.Language.ThrowStatementAst]}, $true))
    if ($substantiveCommands.Count -eq 0 -and $assertions.Count -eq 0) { throw "Verification script is a generic success/output stub: $Path" }
    return [pscustomobject]@{sha256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant();structuralCheck='Non-empty, parseable, contains execution/assertion logic';coverageRequiresGPTReview=$true}
}

function Copy-AutomationBuildTree {
    param([string]$Root, [string]$Source, [string]$Destination)
    $Destination = Resolve-AutomationVerificationPath $Root $Destination
    if (Test-Path -LiteralPath $Destination) { throw "Refusing preexisting clean-build destination: $Destination" }
    $pending = New-Object 'System.Collections.Generic.Queue[object]'
    $pending.Enqueue([pscustomobject]@{source=$Source;destination=$Destination})
    while ($pending.Count -gt 0) {
        $pair = $pending.Dequeue()
        $destinationDirectory = Resolve-AutomationVerificationPath $Root $pair.destination
        if (Test-Path -LiteralPath $destinationDirectory) { throw "Refusing preexisting clean-build destination: $destinationDirectory" }
        [void][IO.Directory]::CreateDirectory($destinationDirectory)
        foreach ($item in @(Get-ChildItem -LiteralPath $pair.source -Force)) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Reparse point in build input: $($item.FullName)" }
            if (Test-SensitivePath $item.Name) { continue }
            if ($item.PSIsContainer) {
                if ($item.Name -in @('.git','target','node_modules','dist','build','.gradle','.m2','.venv','venv','__pycache__')) { continue }
                $pending.Enqueue([pscustomobject]@{source=$item.FullName;destination=(Resolve-AutomationVerificationPath $Root (Join-Path $destinationDirectory $item.Name))})
            } else {
                $destinationFile = Resolve-AutomationVerificationPath $Root (Join-Path $destinationDirectory $item.Name)
                if (Test-Path -LiteralPath $destinationFile) { throw "Refusing preexisting clean-build destination: $destinationFile" }
                Copy-Item -LiteralPath $item.FullName -Destination $destinationFile
            }
        }
    }
}

function Test-AutomationEvidenceSecretIndicators {
    param([string]$Path)
    if ((Get-Item -LiteralPath $Path).Length -gt 32MB) { throw 'Text evidence exceeds the bounded secret inspection limit.' }
    $text = [string](Get-Content -LiteralPath $Path -Raw -Encoding UTF8)
    if ($text -match '(?im)-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|\bBearer\s+(?!\[?REDACTED\]?)[A-Za-z0-9._~+/-]{12,}|\b(?:sk-|ghp_|github_pat_)[A-Za-z0-9_-]{15,}') { return $true }
    foreach ($match in [regex]::Matches($text, '(?im)\b(?:password|api[_-]?key|access[_-]?token|client[_-]?secret)["'']?\s*[=:]\s*["'']?([^\s"''<>;,]+)')) {
        if ($match.Groups[1].Value -notmatch '^(\$\{|\[?REDACTED\]?|<|example|placeholder|changeme|test-only|not-set|null|none|false|true)') { return $true }
    }
    return $false
}

function Protect-AutomationVerificationText {
    param([string]$Text)
    $Text = $Text -replace '(?im)(Authorization\s*:\s*Bearer\s+)[^\s]+', '$1[REDACTED]'
    $Text = $Text -replace '(?im)(\b(?:password|api[_-]?key|access[_-]?token|client[_-]?secret)\s*[=:]\s*)[^\s;,]+', '$1[REDACTED]'
    return $Text
}

function Invoke-AutomationVerification {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)]$Task, [Parameter(Mandatory)]$Plan, [Parameter(Mandatory)][string]$RunDirectory, [Parameter(Mandatory)]$Config)
    $Root = [IO.Path]::GetFullPath($Root).TrimEnd([char[]]'\/')
    $taskId = [string]$Task.id
    if ($taskId -notmatch '^T(?:0[1-9]|[1-3][0-9]|4[0-2])$') { throw 'Invalid verification task ID.' }
    $runPath = Resolve-AutomationVerificationPath $Root $RunDirectory
    $runRelative = Get-AutomationVerificationRelativePath $Root $runPath
    if ($runRelative -notmatch '^docs/execution/runs/') { throw 'Independent verification must stage only under ignored docs/execution/runs/.' }
    [void][IO.Directory]::CreateDirectory($runPath)
    $directory = Join-Path $runPath ('verification-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
    [void][IO.Directory]::CreateDirectory($directory)
    $checks = New-Object 'System.Collections.Generic.List[object]'
    $failures = New-Object 'System.Collections.Generic.List[string]'
    $evidence = New-Object 'System.Collections.Generic.List[string]'
    $startedAt = [DateTime]::UtcNow
    $started = $startedAt.ToString('o')
    $mappings = @(); $externalGates = @()
    $before = Get-AutomationVerificationSnapshot $Root $taskId
    $timeout = [int]$Config.verificationTimeoutSeconds
    if ($timeout -lt 1 -or $timeout -gt 7200) { throw 'verificationTimeoutSeconds must be 1..7200.' }
    $hostExecutable = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $addCheck = {
        param([string]$Name, [bool]$Passed, $Details, $Paths)
        $checks.Add([pscustomobject]@{name=$Name;passed=$Passed;details=$Details;evidencePaths=@($Paths)})
        foreach ($item in @($Paths)) { if ($item) { $evidence.Add((Get-AutomationVerificationRelativePath $Root $item)) } }
        if (-not $Passed) { $failures.Add($Name + ': ' + [string]$Details) }
    }
    try {
        if ([string]$Plan.taskId -cne $taskId) { throw 'Verification plan taskId does not match task.' }
        $scripts = @($Plan.verificationScripts)
        if ($scripts.Count -eq 0) { throw 'Missing verificationScripts; no task can pass from empty checks.' }
        $mappings = @($Plan.acceptanceMapping)
        if ($Plan.PSObject.Properties.Name -contains 'externalGates') { $externalGates = @($Plan.externalGates) }
        if ($mappings.Count -eq 0) { throw 'Missing acceptanceMapping.' }
        foreach ($mapping in $mappings) {
            if (-not ([string]$mapping.criterion).Trim() -or @($mapping.evidenceExpected).Count -eq 0) { throw 'Each acceptance criterion needs explicit evidence paths.' }
            foreach ($path in @($mapping.evidenceExpected)) {
                $full = Resolve-AutomationVerificationPath $Root ([string]$path)
                $relative = Get-AutomationVerificationRelativePath $Root $full
                if ((Test-SensitivePath $relative) -or $relative -notmatch ('^(docs/verification/' + [regex]::Escape($taskId) + '/|docs/execution/runs/)')) { throw "Acceptance evidence must be a non-sensitive task evidence/run file: $relative" }
            }
        }
        $index = 0
        foreach ($script in $scripts) {
            $index++
            $relative = ([string]$script).Replace('\','/')
            if ($relative -notmatch '^(scripts/verify/|tests/).+\.ps1$' -or [IO.Path]::IsPathRooted($relative)) { throw "Verification script is outside allowed directories: $relative" }
            $scriptPath = Resolve-AutomationVerificationPath $Root $relative -MustExist
            $meaningful = Test-AutomationVerificationScript $scriptPath
            $commandDirectory = Join-Path $directory ('script-' + $index.ToString('00'))
            [void][IO.Directory]::CreateDirectory($commandDirectory)
            $execution = Invoke-AutomationCommand -Root $Root -Command $hostExecutable -Arguments @('-NoLogo','-NoProfile','-NonInteractive','-File',$scriptPath) -RunDirectory $commandDirectory -MaxRunSeconds $timeout
            & $addCheck ('Feature verification: ' + $relative) ($execution.exitCode -eq 0 -and -not $execution.timedOut) ([pscustomobject]@{command=$hostExecutable;arguments=@('-NoProfile','-NonInteractive','-File',$relative);exitCode=$execution.exitCode;timedOut=$execution.timedOut;durationSeconds=$execution.durationSeconds;script=$meaningful}) @($execution.evidencePaths)
        }
        foreach ($mapping in $mappings) {
            foreach ($path in @($mapping.evidenceExpected)) {
                $full = Resolve-AutomationVerificationPath $Root ([string]$path) -MustExist
                if ((Get-Item -LiteralPath $full).Length -eq 0) { throw "Empty acceptance evidence: $path" }
                if ((Get-Item -LiteralPath $full).LastWriteTimeUtc -lt $startedAt.AddSeconds(-2)) { throw "Stale acceptance evidence was not refreshed by independent verification: $path" }
                $evidence.Add((Get-AutomationVerificationRelativePath $Root $full))
            }
        }
        if ($taskId -eq 'T01') {
            # These are the supplied files' immutable preparation-time hashes.
            $originals = [ordered]@{
                'Booking_Application_Master_Execution_Plan.md'='b44eb6715ddad112056b3c5b3710f6e99bcbb3743211b3e8d234851ae525e258'
                'Booking_Backend_Local_Agent_Execution_Plan.md'='28e9b5addbb66fad2f68dcd94714160f88d404fcfbb49a2b15683fd476b92956'
                'Booking_Application_Design_and_Development.docx'='a01d73e5a28ec5840a2ee81830fc83f829cd118fe9826a71de2d01c4da2385dc'
            }
            $sourceChecks = @()
            foreach ($name in $originals.Keys) {
                $sourcePath = Resolve-AutomationVerificationPath $Root $name -MustExist
                $actual = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
                $sourceChecks += [pscustomobject]@{path=$name;expectedSha256=$originals[$name];actualSha256=$actual;passed=($actual -ceq $originals[$name])}
            }
            $sourceReport = Join-Path $directory 'original-source-hashes.json'
            Write-NewJson $sourceReport $sourceChecks
            & $addCheck 'T01 supplied source preservation' (@($sourceChecks | Where-Object {-not $_.passed}).Count -eq 0) $sourceChecks @($sourceReport)

            $pomPath = Resolve-AutomationVerificationPath $Root 'pom.xml' -MustExist
            [xml]$pom = Get-Content -LiteralPath $pomPath -Raw -Encoding UTF8
            $properties = $pom.project.properties
            $javaVersion = [string]$properties.'java.version'
            $bootVersion = [string]$properties.'spring-boot.version'
            $aiVersion = [string]$properties.'spring-ai.version'
            if ($javaVersion -ne '25' -or $bootVersion -notmatch '^4\.\d+\.\d+$' -or $aiVersion -notmatch '^\d+\.\d+\.\d+$') { throw 'T01 Java 25 / stable Spring Boot 4.x / Spring AI pins are missing.' }
            $pomFiles = @($before.files | Where-Object { $_.path -match '(^|/)pom\.xml$' })
            foreach ($file in $pomFiles) {
                $text = Get-Content -LiteralPath (Resolve-AutomationVerificationPath $Root $file.path -MustExist) -Raw -Encoding UTF8
                if ($text -match '(?i)<[A-Za-z0-9_.-]*version>\s*(latest|release|[^<]*snapshot|[^<]*-(?:M|RC|alpha|beta)\d*)\s*</') { throw "Unstable/unpinned version in $($file.path)." }
            }
            $wrapperPath = Resolve-AutomationVerificationPath $Root '.mvn/wrapper/maven-wrapper.properties' -MustExist
            $wrapper = Get-Content -LiteralPath $wrapperPath -Raw -Encoding UTF8 | ConvertFrom-StringData
            $url = [string]$wrapper.distributionUrl
            $checksum = [string]$wrapper.distributionSha256Sum
            $uri = New-Object Uri($url)
            if ($uri.Scheme -ne 'https' -or $uri.Host -notmatch '^(archive\.apache\.org|dlcdn\.apache\.org|downloads\.apache\.org|repo\.maven\.apache\.org)$' -or $url -notmatch '/apache-maven-(\d+\.\d+\.\d+)-bin\.zip$' -or $checksum -notmatch '^[a-fA-F0-9]{64}$') { throw 'Pinned official HTTPS Maven ZIP and SHA-256 checksum are required.' }
            $mavenVersion = [regex]::Match($url, '/apache-maven-(\d+\.\d+\.\d+)-bin\.zip$').Groups[1].Value
            $manifestPath = Resolve-AutomationVerificationPath $Root 'docs/execution/dependency-manifest.json' -MustExist
            $manifestText = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8
            $manifest = $manifestText | ConvertFrom-Json
            if (@($manifest.PSObject.Properties).Count -eq 0 -or $manifestText -notmatch 'https://(?:docs\.)?spring\.io/' -or $manifestText -notmatch '\d{4}-\d{2}-\d{2}') { throw 'T01 dependency manifest needs version/date/official-source evidence.' }
            foreach ($version in @($javaVersion,$bootVersion,$aiVersion,$mavenVersion)) {
                if ($manifestText -notmatch [regex]::Escape($version)) { throw "Dependency manifest does not include selected version $version." }
            }
            $adr = @($before.files | Where-Object { $_.path -match '^docs/(adr|architecture/adr)/.*(compatib|baseline|dependenc).*\.md$' } | Where-Object {
                $text = Get-Content -LiteralPath (Resolve-AutomationVerificationPath $Root $_.path -MustExist) -Raw -Encoding UTF8
                $text.Length -ge 150 -and $text -match 'https://(?:docs\.)?spring\.io/' -and $text -match '(?i)compatib'
            })
            if ($adr.Count -eq 0) { throw 'T01 requires a substantive compatibility ADR with official-source references.' }
            $pinReport = Join-Path $directory 'dependency-pins.json'
            Write-NewJson $pinReport ([ordered]@{java=$javaVersion;springBoot=$bootVersion;springAI=$aiVersion;maven=$mavenVersion;distributionUrl=$url;declaredSha256=$checksum;manifest='docs/execution/dependency-manifest.json';compatibilityADR=@($adr.path);declaredPinsAloneProveCompatibility=$false})
            & $addCheck 'T01 dependency declarations and evidence presence' $true 'Stable declarations and references exist; actual resolution/build and GPT source review remain required.' (@($pinReport,$manifestPath)+@($adr | ForEach-Object {Resolve-AutomationVerificationPath $Root $_.path}))

            $downloadDirectory = Resolve-AutomationVerificationPath $Root (Join-Path $directory 'distribution-check')
            if (Test-Path -LiteralPath $downloadDirectory) { throw 'Refusing preexisting distribution-check directory.' }
            [void][IO.Directory]::CreateDirectory($downloadDirectory)
            $downloadRequest = Join-Path $downloadDirectory 'request.json'
            Write-NewJson $downloadRequest ([ordered]@{url=$url;sha256=$checksum;destination=(Join-Path $downloadDirectory 'maven-distribution.zip');report=(Join-Path $downloadDirectory 'distribution-proof.json');timeoutSeconds=([Math]::Min(240,$timeout))})
            $downloadScript = Join-Path $downloadDirectory 'verify-distribution.ps1'
            Write-NewUtf8 $downloadScript @'
param([string]$RequestPath)
$ErrorActionPreference = 'Stop'
$request = Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $request.url -OutFile $request.destination -UseBasicParsing -TimeoutSec $request.timeoutSeconds
if ((Get-Item -LiteralPath $request.destination).Length -gt 100MB) { throw 'Maven distribution exceeds expected maximum size.' }
$actual256 = (Get-FileHash -LiteralPath $request.destination -Algorithm SHA256).Hash.ToLowerInvariant()
$actual512 = (Get-FileHash -LiteralPath $request.destination -Algorithm SHA512).Hash.ToLowerInvariant()
$officialChecksumUrl = $request.url + '.sha512'
$official = (Invoke-WebRequest -Uri $officialChecksumUrl -UseBasicParsing -TimeoutSec $request.timeoutSeconds).Content
if ($official -is [byte[]]) { $official = [Text.Encoding]::UTF8.GetString($official) }
if ([string]$official -notmatch '(?i)\b([a-f0-9]{128})\b') { throw 'Official SHA-512 checksum is absent or malformed.' }
$expected512 = $Matches[1].ToLowerInvariant()
$proof = [ordered]@{url=$request.url;sha256=$actual256;declaredSha256=$request.sha256;officialChecksumUrl=$officialChecksumUrl;actualSha512=$actual512;officialSha512=$expected512;passed=($actual256 -ceq $request.sha256.ToLowerInvariant() -and $actual512 -ceq $expected512);checkedAt=[DateTime]::UtcNow.ToString('o')}
[IO.File]::WriteAllText($request.report,($proof | ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
if (-not $proof.passed) { throw 'Maven distribution failed declared SHA-256 or official SHA-512 verification.' }
exit 0
'@
            $download = Invoke-AutomationCommand -Root $Root -Command $hostExecutable -Arguments @('-NoLogo','-NoProfile','-NonInteractive','-File',$downloadScript,'-RequestPath',$downloadRequest) -RunDirectory $downloadDirectory -MaxRunSeconds ([Math]::Min(300,$timeout))
            $proofPath = Join-Path $downloadDirectory 'distribution-proof.json'
            $proofValid = $false
            if (Test-Path -LiteralPath $proofPath -PathType Leaf) {
                $proof = Read-WorkflowJson $proofPath
                $proofValid = ($proof.passed -eq $true -and $proof.sha256 -ceq $checksum.ToLowerInvariant())
                $evidence.Add((Get-AutomationVerificationRelativePath $Root $proofPath))
            }
            & $addCheck 'T01 independent Maven distribution checksum' ($download.exitCode -eq 0 -and -not $download.timedOut -and $proofValid) ([pscustomobject]@{exitCode=$download.exitCode;timedOut=$download.timedOut;checksumProofValid=$proofValid}) @($download.evidencePaths)

            $stage = Resolve-AutomationVerificationPath $Root (Join-Path $directory 'clean-stage')
            if (Test-Path -LiteralPath $stage) { throw 'Refusing preexisting clean-stage directory.' }
            [void][IO.Directory]::CreateDirectory($stage)
            foreach ($name in @('pom.xml','mvnw','mvnw.cmd','.editorconfig','.gitignore')) {
                $path = Resolve-AutomationVerificationPath $Root $name
                if (Test-Path -LiteralPath $path -PathType Leaf) { Copy-Item -LiteralPath $path -Destination (Resolve-AutomationVerificationPath $Root (Join-Path $stage $name)) }
            }
            $mvnDirectory = Resolve-AutomationVerificationPath $Root '.mvn'
            if (-not (Test-Path -LiteralPath $mvnDirectory -PathType Container)) { throw 'Missing Maven wrapper directory.' }
            Copy-AutomationBuildTree $Root $mvnDirectory (Join-Path $stage '.mvn')
            foreach ($module in @($pom.project.modules.module)) {
                $moduleName = [string]$module
                $moduleSource = Resolve-AutomationVerificationPath $Root $moduleName
                if (-not (Test-Path -LiteralPath $moduleSource -PathType Container) -or $moduleName -match '(^|[\\/])\.\.([\\/]|$)' -or [IO.Path]::IsPathRooted($moduleName)) { throw "Invalid Maven module path: $moduleName" }
                Copy-AutomationBuildTree $Root $moduleSource (Join-Path $stage $moduleName)
            }
            $stageInputs = @()
            foreach ($file in @(Get-ChildItem -LiteralPath $stage -File -Recurse -Force)) {
                $stageInputs += [pscustomobject]@{path=$file.FullName.Substring($stage.Length+1).Replace('\','/');sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
            }
            $stageManifest = Join-Path $directory 'clean-stage-inputs.json'
            Write-NewJson $stageManifest ([ordered]@{stage=(Get-AutomationVerificationRelativePath $Root $stage);copiedFromCurrentSource=$true;externalStagingPointerUsed=$false;files=$stageInputs})
            $evidence.Add((Get-AutomationVerificationRelativePath $Root $stageManifest))
            $wrapperCommand = Join-Path $stage 'mvnw.cmd'
            if (-not (Test-Path -LiteralPath $wrapperCommand -PathType Leaf)) { throw 'Missing Windows Maven wrapper.' }
            $previousMavenHome = $env:MAVEN_USER_HOME
            $previousWrapperRepo = $env:MVNW_REPOURL
            try {
                $mavenHome = Resolve-AutomationVerificationPath $Root (Join-Path $stage '.m2')
                if (Test-Path -LiteralPath $mavenHome) { throw 'Refusing preexisting clean-stage Maven cache.' }
                [void][IO.Directory]::CreateDirectory($mavenHome)
                $mavenRepository = Resolve-AutomationVerificationPath $Root (Join-Path $mavenHome 'repository')
                $env:MAVEN_USER_HOME = $mavenHome
                $env:MVNW_REPOURL = $null
                $buildDirectory = Resolve-AutomationVerificationPath $Root (Join-Path $directory 'clean-build')
                if (Test-Path -LiteralPath $buildDirectory) { throw 'Refusing preexisting clean-build log directory.' }
                [void][IO.Directory]::CreateDirectory($buildDirectory)
                $buildArguments = @('-B','-ntp',('-Dmaven.repo.local=' + $mavenRepository),'clean','verify')
                $build = Invoke-AutomationCommand -Root $stage -Command $wrapperCommand -Arguments $buildArguments -RunDirectory $buildDirectory -MaxRunSeconds $timeout
            } finally { $env:MAVEN_USER_HOME = $previousMavenHome; $env:MVNW_REPOURL = $previousWrapperRepo }
            & $addCheck 'T01 actual clean-stage Maven wrapper clean verify' ($build.exitCode -eq 0 -and -not $build.timedOut) ([pscustomobject]@{command='mvnw.cmd';arguments=$buildArguments;workingDirectory=(Get-AutomationVerificationRelativePath $Root $stage);exitCode=$build.exitCode;timedOut=$build.timedOut;durationSeconds=$build.durationSeconds;globalJdkInstalled=$false;inheritedJavaHome=([bool]$env:JAVA_HOME)}) @($build.evidencePaths)
        }
    } catch {
        $message = Protect-AutomationVerificationText ([string]$_.Exception.Message)
        $failures.Add($message)
        $checks.Add([pscustomobject]@{name='Verification contract/execution failure';passed=$false;details=$message;evidencePaths=@()})
    }
    $after = Get-AutomationVerificationSnapshot $Root $taskId
    $changed = @(Get-ChangedSourcePaths $before $after)
    & $addCheck 'Verification preserves source and supervisor state' ($changed.Count -eq 0) ([pscustomobject]@{unexpectedChangedPaths=$changed}) @()
    $inspectionPaths = @($evidence | Sort-Object -Unique)
    foreach ($path in $inspectionPaths) {
        try {
            $full = Resolve-AutomationVerificationPath $Root $path -MustExist
            if ($path -match '(?i)\.(log|txt|md|json|ya?ml|xml|properties|csv)$' -and (Test-AutomationEvidenceSecretIndicators $full)) { throw "Credential indicator in evidence: $path" }
        } catch { $failures.Add((Protect-AutomationVerificationText ([string]$_.Exception.Message))) }
    }
    $hashes = @()
    foreach ($path in $inspectionPaths) {
        try {
            $full = Resolve-AutomationVerificationPath $Root $path -MustExist
            $hashes += [pscustomobject]@{path=$path;sha256=(Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant();bytes=(Get-Item -LiteralPath $full).Length}
        } catch { $failures.Add((Protect-AutomationVerificationText ([string]$_.Exception.Message))) }
    }
    $reportPath = Join-Path $directory 'verification-report.json'
    $report = [ordered]@{schemaVersion='1.0';taskId=$taskId;startedAt=$started;finishedAt=[DateTime]::UtcNow.ToString('o');passed=($failures.Count -eq 0 -and $checks.Count -ge 2);checks=$checks.ToArray();failureReasons=$failures.ToArray();sourceSnapshotBefore=$before;sourceSnapshotAfter=$after;unexpectedChangedPaths=$changed;acceptanceMapping=$mappings;externalGates=$externalGates;evidence=$hashes;taskApproval='REQUIRES_INDEPENDENT_GPT_REVIEW';limitations=@('Script structural checks cannot prove full behavioral coverage; GPT must inspect source and criterion coverage.','Mapped criterion evidence must be refreshed during independent verification; a two-second filesystem timestamp tolerance applies.','Credential scan is bounded pattern detection, not a claim of exhaustive secret discovery.')}
    Write-NewJson $reportPath $report
    return [pscustomobject]@{passed=$report.passed;checks=$checks.ToArray();evidencePaths=@($inspectionPaths)+@((Get-AutomationVerificationRelativePath $Root $reportPath));reportPath=(Get-AutomationVerificationRelativePath $Root $reportPath);failureReasons=$failures.ToArray()}
}
