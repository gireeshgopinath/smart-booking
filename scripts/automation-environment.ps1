# Environment management and synthetic admission for the unattended task coordinator.
# Dot-source this file. No service or model is changed merely by importing it.
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'workflow-common.ps1')

function Get-AutomationEnvironmentOption {
    param($Config, [string]$Name, $Default)
    if ($null -ne $Config -and @($Config.PSObject.Properties.Name) -contains $Name) { return $Config.$Name }
    return $Default
}

function Get-AutomationEnvironmentDirectory {
    param([string]$Root, [string]$RunDirectory)
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd([char[]]'\/')
    $path = if ([IO.Path]::IsPathRooted($RunDirectory)) { [IO.Path]::GetFullPath($RunDirectory) } else { Resolve-WorkspacePath $rootPath $RunDirectory }
    if (-not $path.StartsWith($rootPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Environment evidence must remain inside the workspace.' }
    Assert-AutomationEnvironmentPathAncestors $rootPath $path
    if (-not (Test-Path -LiteralPath $path)) { [void][IO.Directory]::CreateDirectory($path) }
    return $path
}

function Assert-AutomationEnvironmentPathAncestors {
    param([string]$Root,[string]$Path)
    $rootPath=[IO.Path]::GetFullPath($Root).TrimEnd([char[]]'\/')
    $cursor=[IO.Path]::GetFullPath($Path)
    while ($cursor.Length -gt $rootPath.Length) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Environment path has a reparse-point ancestor.' }
        }
        $cursor=Split-Path -Parent $cursor
    }
}

function ConvertTo-AutomationEnvironmentEvidencePath {
    param([string]$Root, [string]$Path)
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd([char[]]'\/')
    $fullPath = [IO.Path]::GetFullPath($Path)
    if (-not $fullPath.StartsWith($rootPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Evidence path escapes the workspace.' }
    return $fullPath.Substring($rootPath.Length + 1).Replace('\','/')
}

function Get-AutomationEnvironmentCommand {
    param([string]$Name)
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -eq $command) { return $null }
    return $command.Source
}

function Invoke-AutomationEnvironmentNative {
    param([string]$Command, [string[]]$Arguments, [string]$RunDirectory, [int]$MaxRunSeconds = 30)
    $directory = Join-Path $RunDirectory ('probe-' + [Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($directory)
    $promptPath = Join-Path $directory 'stdin.txt'
    Write-NewUtf8 $promptPath ''
    $outcome = Invoke-BoundedCodex -Command $Command -Arguments $Arguments -PromptPath $promptPath -Directory $directory -MaxRunSeconds $MaxRunSeconds
    $stdout = [IO.File]::ReadAllText((Join-Path $directory 'codex.stdout.log'))
    $stderr = [IO.File]::ReadAllText((Join-Path $directory 'codex.stderr.log'))
    return [pscustomobject]@{ exitCode=$outcome.exitCode; timedOut=$outcome.timedOut; output=$stdout; errorOutput=$stderr; directory=$directory }
}

function Get-AutomationJavaCandidates {
    param([string]$Root)
    $candidates = New-Object 'System.Collections.Generic.List[string]'
    if ($env:JAVA_HOME) { $candidates.Add((Join-Path $env:JAVA_HOME 'bin/java.exe')) }
    $fromPath = Get-AutomationEnvironmentCommand 'java'
    if ($fromPath) { $candidates.Add($fromPath) }
    $bases = @((Join-Path $Root '.tools/jdk25'))
    foreach ($programPath in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($programPath) {
            foreach ($vendor in @('Eclipse Adoptium','Java','Microsoft','Amazon Corretto','Zulu')) { $bases += Join-Path $programPath $vendor }
        }
    }
    foreach ($base in $bases) {
        if (-not (Test-Path -LiteralPath $base)) { continue }
        $direct = Join-Path $base 'bin/java.exe'
        if (Test-Path -LiteralPath $direct) { $candidates.Add($direct) }
        foreach ($child in @(Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue)) {
            if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            $candidate = Join-Path $child.FullName 'bin/java.exe'
            if (Test-Path -LiteralPath $candidate) { $candidates.Add($candidate) }
            # Portable archives have an owned extraction directory and one vendor top directory.
            if ($base -eq (Join-Path $Root '.tools/jdk25')) {
                foreach ($grandchild in @(Get-ChildItem -LiteralPath $child.FullName -Directory -ErrorAction SilentlyContinue)) {
                    if ($grandchild.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                    $candidate=Join-Path $grandchild.FullName 'bin/java.exe'
                    if (Test-Path -LiteralPath $candidate) { $candidates.Add($candidate) }
                }
            }
        }
    }
    return @($candidates | Sort-Object -Unique)
}

function Find-AutomationJava25 {
    param([string]$Root, [string]$RunDirectory)
    foreach ($candidate in @(Get-AutomationJavaCandidates $Root)) {
        if (-not (Test-Path -LiteralPath $candidate)) { continue }
        $probe = Invoke-AutomationEnvironmentNative $candidate @('-version') $RunDirectory 30
        $version = ($probe.output + "`n" + $probe.errorOutput).Trim()
        if ($probe.exitCode -eq 0 -and $version -match '(?:java|openjdk) version\s+"25(?:[.\-+\"])') {
            return [pscustomobject]@{ ready=$true; executable=$candidate; javaHome=(Split-Path -Parent (Split-Path -Parent $candidate)); version=$version }
        }
    }
    return [pscustomobject]@{ ready=$false; executable=$null; javaHome=$null; version=$null }
}

function Get-AutomationJdkMetadata {
    $uri = 'https://api.adoptium.net/v3/assets/latest/25/hotspot?architecture=x64&heap_size=normal&image_type=jdk&jvm_impl=hotspot&os=windows&vendor=eclipse'
    $metadata = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 30
    $matches = @($metadata | Where-Object { $_.binary.os -eq 'windows' -and $_.binary.architecture -eq 'x64' -and $_.binary.image_type -eq 'jdk' -and $_.version.major -eq 25 })
    if ($matches.Count -eq 0) { throw 'Adoptium did not return a Windows x64 JDK 25.' }
    $asset = $matches[0]
    $package = $asset.binary.package
    if ($package.checksum -notmatch '^[a-fA-F0-9]{64}$') { throw 'JDK metadata has no valid SHA-256 checksum.' }
    if ($package.link -notmatch '^https://github\.com/adoptium/temurin25-binaries/releases/download/[^\s]+\.zip$') { throw 'Unexpected JDK download origin or archive format.' }
    if ([long]$package.size -lt 1MB -or [long]$package.size -gt 1GB) { throw 'JDK archive size is outside the bounded range.' }
    return [pscustomobject]@{ metadataUrl=$uri; link=$package.link; sha256=$package.checksum.ToLowerInvariant(); size=[long]$package.size; release=$asset.release_name; version=$asset.version.semver }
}

function Invoke-AutomationJdkDownload {
    param($Metadata, [string]$ArchivePath, [string]$RunDirectory)
    $helperPath = Join-Path $RunDirectory 'download-jdk.ps1'
    $requestPath = Join-Path $RunDirectory 'download-jdk-request.json'
    Write-NewJson $requestPath ([ordered]@{ uri=$Metadata.link; destination=$ArchivePath; maxBytes=1GB })
    Write-NewUtf8 $helperPath @'
param([string]$RequestPath)
$ErrorActionPreference = 'Stop'
$request = Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json
Invoke-WebRequest -Uri $request.uri -OutFile $request.destination -TimeoutSec 240 -UseBasicParsing
if ((Get-Item -LiteralPath $request.destination).Length -gt $request.maxBytes) { throw 'JDK download exceeded the byte limit.' }
'@
    $hostExecutable = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $download = Invoke-AutomationEnvironmentNative $hostExecutable @('-NoLogo','-NoProfile','-NonInteractive','-File',$helperPath,'-RequestPath',$requestPath) $RunDirectory 300
    if ($download.exitCode -ne 0) { throw ('Portable JDK download failed or exceeded its deadline; exit ' + $download.exitCode) }
}

function Install-AutomationPortableJava25 {
    param([string]$Root, [string]$RunDirectory)
    $metadata = Get-AutomationJdkMetadata
    $toolsPath = Resolve-WorkspacePath $Root '.tools'
    $parentPath = Resolve-WorkspacePath $Root '.tools/jdk25'
    Assert-AutomationEnvironmentPathAncestors $Root $parentPath
    foreach ($path in @($toolsPath,$parentPath)) {
        if (Test-Path -LiteralPath $path) {
            if ((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Portable tool path is a reparse point.' }
        } else { [void][IO.Directory]::CreateDirectory($path) }
    }
    $token = [Guid]::NewGuid().ToString('N')
    $archivePath = Join-Path $parentPath ($token + '.zip')
    $extractPath = Join-Path $parentPath ('jdk-' + $token)
    Write-NewJson (Join-Path $RunDirectory 'jdk-download-metadata.json') $metadata
    Invoke-AutomationJdkDownload $metadata $archivePath $RunDirectory
    if (-not (Test-Path -LiteralPath $archivePath)) { throw 'JDK downloader returned without an archive.' }
    $archive = Get-Item -LiteralPath $archivePath
    if ($archive.Length -ne $metadata.size) { throw 'JDK archive size does not match official metadata.' }
    $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-NewJson (Join-Path $RunDirectory 'jdk-download-checksum.json') ([ordered]@{ release=$metadata.release; expected=$metadata.sha256; actual=$actualHash; bytes=$archive.Length; match=($actualHash -ceq $metadata.sha256) })
    if ($actualHash -cne $metadata.sha256) { throw 'JDK archive checksum mismatch; archive was not extracted.' }
    # Validate every ZIP member before extracting anything, including Windows ADS and traversal.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    Add-Type -AssemblyName System.IO.Compression
    $zip = [IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        $extractPrefix = [IO.Path]::GetFullPath($extractPath).TrimEnd([char[]]'\/') + [IO.Path]::DirectorySeparatorChar
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName -match ':' -or [IO.Path]::IsPathRooted($entry.FullName)) { throw 'Unsafe absolute or alternate-stream JDK ZIP member.' }
            if ((($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) { throw 'Symlink entries are not permitted in portable JDK archives.' }
            $destination = [IO.Path]::GetFullPath((Join-Path $extractPath $entry.FullName))
            if (-not $destination.StartsWith($extractPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'JDK ZIP member escapes extraction directory.' }
        }
    } finally { $zip.Dispose() }
    $helperPath = Join-Path $RunDirectory 'extract-jdk.ps1'
    $requestPath = Join-Path $RunDirectory 'extract-jdk-request.json'
    Write-NewJson $requestPath ([ordered]@{ archive=$archivePath; destination=$extractPath })
    Write-NewUtf8 $helperPath @'
param([string]$RequestPath)
$ErrorActionPreference = 'Stop'
$request = Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json
Expand-Archive -LiteralPath $request.archive -DestinationPath $request.destination
'@
    $hostExecutable = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $extraction = Invoke-AutomationEnvironmentNative $hostExecutable @('-NoLogo','-NoProfile','-NonInteractive','-File',$helperPath,'-RequestPath',$requestPath) $RunDirectory 180
    if ($extraction.exitCode -ne 0) { throw ('JDK extraction failed or timed out; exit ' + $extraction.exitCode) }
    $executables = @(Get-ChildItem -LiteralPath $extractPath -Filter java.exe -File -Recurse | Where-Object { $_.Directory.Name -eq 'bin' })
    if ($executables.Count -ne 1) { throw 'Portable JDK archive did not contain exactly one bin/java.exe.' }
    $candidate = $executables[0].FullName
    $probe = Invoke-AutomationEnvironmentNative $candidate @('-version') $RunDirectory 30
    $version = ($probe.output + "`n" + $probe.errorOutput).Trim()
    if ($probe.exitCode -ne 0 -or $version -notmatch '(?:java|openjdk) version\s+"25(?:[.\-+\"])') { throw 'Installed portable Java did not verify as version 25.' }
    # Keep the verified archive and metadata for reproducibility. No system installation is performed.
    return [pscustomobject]@{ ready=$true; executable=$candidate; javaHome=(Split-Path -Parent (Split-Path -Parent $candidate)); version=$version; release=$metadata.release; checksum=$actualHash }
}

function Get-AutomationLoadedLocalModels {
    param([string]$Command, [string]$RunDirectory)
    $probe = Invoke-AutomationEnvironmentNative $Command @('ps','--json') $RunDirectory 30
    if ($probe.exitCode -ne 0) { throw 'Could not verify LM Studio model activity.' }
    try {
        $parsed=$probe.output | ConvertFrom-Json
        # Windows PowerShell 5.1 emits JSON arrays as one pipeline object; flatten explicitly.
        foreach ($model in $parsed) { Write-Output $model }
    } catch { throw 'LM Studio activity was not valid JSON.' }
}

function Test-AutomationLocalModelsBusy {
    param([object[]]$Models)
    foreach ($model in @($Models)) {
        if ($model.type -ne 'llm') { continue }
        $fields = @($model.PSObject.Properties.Name)
        if ($fields -notcontains 'status' -or $model.status -notin @('idle','unloaded') -or ($fields -contains 'queued' -and [int]$model.queued -gt 0)) { return $true }
    }
    return $false
}

function Initialize-AutomationLocalModel {
    param($Config, [string]$RunDirectory)
    $issues = New-Object 'System.Collections.Generic.List[string]'
    $unavailable = [pscustomobject]@{ available=$false; model=$null; issues=@(); loadedModels=@() }
    $command = Get-AutomationEnvironmentCommand 'lms'
    if (-not $command) { $unavailable.issues=@('LM Studio CLI is unavailable; no model was downloaded.'); return $unavailable }
    try {
        foreach ($name in @('CODEX_OSS_BASE_URL','CODEX_OSS_PORT','OLLAMA_BASE_URL','LMSTUDIO_BASE_URL')) {
            if ([Environment]::GetEnvironmentVariable($name)) { throw "Unverified provider override $name is present." }
        }
        $loaded = @(Get-AutomationLoadedLocalModels $command $RunDirectory)
        $waitSeconds = [int](Get-AutomationEnvironmentOption $Config 'modelBusyWaitSeconds' 30)
        $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Max(0,$waitSeconds))
        while ((Test-AutomationLocalModelsBusy $loaded) -and [DateTime]::UtcNow -lt $deadline) {
            Start-Sleep -Milliseconds 1000
            $loaded = @(Get-AutomationLoadedLocalModels $command $RunDirectory)
        }
        if (Test-AutomationLocalModelsBusy $loaded) { throw 'LM Studio has active, queued or unverifiable generation; it was left untouched.' }
        $inventoryProbe = Invoke-AutomationEnvironmentNative $command @('ls','--json') $RunDirectory 30
        if ($inventoryProbe.exitCode -ne 0) { throw 'Could not inventory installed local models.' }
        $parsedInventory=$inventoryProbe.output | ConvertFrom-Json
        $installed=@(foreach ($entry in $parsedInventory) { $entry })
        $allowed = @(Get-AutomationEnvironmentOption $Config 'localModels' @('qwen3.8-27b','qwen3.8-flash-next'))
        $matches = @($allowed | Where-Object { $key=$_; @($installed | Where-Object { $_.type -eq 'llm' -and $_.modelKey -ceq $key }).Count -eq 1 })
        if ($matches.Count -eq 0) { throw 'None of the configured model keys is installed; model downloads are disabled.' }
        $manage = [bool](Get-AutomationEnvironmentOption $Config 'manageLocalServices' $true)
        $context = [int](Get-AutomationEnvironmentOption $Config 'localContextLength' 32768)
        $parallel = [int](Get-AutomationEnvironmentOption $Config 'localParallel' 1)
        if ($context -lt 4096 -or $context -gt 262144 -or $parallel -ne 1) { throw 'Local development requires bounded context and exactly one parallel prediction.' }
        $selected = $matches[0]
        if (-not $manage) {
            $usable = @($loaded | Where-Object { $_.type -eq 'llm' -and $matches -ccontains $_.modelKey })
            if ($usable.Count -eq 0) { throw 'No configured installed model is loaded, and local service management is disabled.' }
            $selected = $usable[0].modelKey
            $servedIdentifier = $usable[0].identifier
        } else {
            $already = @($loaded | Where-Object { $_.type -eq 'llm' -and $_.modelKey -ceq $selected -and $_.contextLength -eq $context -and $_.parallel -eq $parallel })
            if ($already.Count -eq 1) { $servedIdentifier=$already[0].identifier }
            else {
                foreach ($model in @($loaded | Where-Object { $_.type -eq 'llm' })) {
                    # Re-check immediately before each mutation; never stop or unload observed active work.
                    $fresh = @(Get-AutomationLoadedLocalModels $command $RunDirectory)
                    if (Test-AutomationLocalModelsBusy $fresh) { throw 'Model became active before switching; existing generation was preserved.' }
                    $stillLoaded = @($fresh | Where-Object { $_.identifier -ceq $model.identifier })
                    if ($stillLoaded.Count -eq 0) { continue }
                    $unload = Invoke-AutomationEnvironmentNative $command @('unload',$model.identifier) $RunDirectory 60
                    if ($unload.exitCode -ne 0) { throw 'Idle model unload failed; no broader process termination was attempted.' }
                }
                $fresh = @(Get-AutomationLoadedLocalModels $command $RunDirectory)
                if (Test-AutomationLocalModelsBusy $fresh) { throw 'Another generation started before model loading; local admission was deferred.' }
                $load = Invoke-AutomationEnvironmentNative $command @('load',$selected,'--context-length',[string]$context,'--parallel','1','--identifier',$selected,'--yes') $RunDirectory 240
                if ($load.exitCode -ne 0) { throw ('Installed local model failed to load; exit ' + $load.exitCode) }
                $servedIdentifier = $selected
            }
        }
        try { $server = Invoke-RestMethod -Uri 'http://127.0.0.1:1234/v1/models' -TimeoutSec 5 }
        catch {
            if (-not $manage) { throw 'LM Studio loopback endpoint is unavailable; service management is disabled.' }
            $start = Invoke-AutomationEnvironmentNative $command @('server','start','--port','1234','--bind','127.0.0.1') $RunDirectory 60
            if ($start.exitCode -ne 0) { throw 'LM Studio loopback server could not be started.' }
            $server = Invoke-RestMethod -Uri 'http://127.0.0.1:1234/v1/models' -TimeoutSec 5
        }
        if (@($server.data | Where-Object { $_.id -ceq $servedIdentifier }).Count -ne 1) { throw 'Exact loaded model identifier is absent from the loopback API inventory.' }
        $fresh = @(Get-AutomationLoadedLocalModels $command $RunDirectory)
        if (Test-AutomationLocalModelsBusy $fresh) { throw 'Model activity changed before admission; active work was preserved.' }
        return [pscustomobject]@{ available=$true; model=$servedIdentifier; issues=@(); loadedModels=$fresh }
    } catch {
        $issues.Add($_.Exception.Message)
        $unavailable.issues=$issues.ToArray()
        return $unavailable
    }
}

function Initialize-AutomationEnvironment {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Root, [Parameter(Mandatory=$true)]$Config, [Parameter(Mandatory=$true)][string]$RunDirectory)
    $directory = Get-AutomationEnvironmentDirectory $Root $RunDirectory
    $issues = New-Object 'System.Collections.Generic.List[string]'
    $java = Find-AutomationJava25 $Root $directory
    if (-not $java.ready -and [bool](Get-AutomationEnvironmentOption $Config 'installPrerequisites' $true)) {
        try { $java = Install-AutomationPortableJava25 $Root $directory } catch { $issues.Add('Java prerequisite: ' + $_.Exception.Message) }
    }
    if ($java.ready) {
        $env:JAVA_HOME=$java.javaHome
        $javaBin=Join-Path $java.javaHome 'bin'
        if (@($env:PATH -split ';') -notcontains $javaBin) { $env:PATH=$javaBin + ';' + $env:PATH }
    } else { $issues.Add('Verified JDK 25 is unavailable; application build acceptance remains blocked.') }
    $local = Initialize-AutomationLocalModel $Config $directory
    foreach ($issue in @($local.issues)) { $issues.Add($issue) }
    $reportPath=Join-Path $directory 'environment-report.json'
    $report=[ordered]@{ observedAt=[DateTime]::UtcNow.ToString('o'); javaReady=[bool]$java.ready; javaHome=$java.javaHome; java=$java; localAvailable=[bool]$local.available; localModel=$local.model; local=$local; issues=$issues.ToArray(); changesScope='Workspace .tools, owned evidence and process-local JAVA_HOME/PATH; idle installed models only.'; globalConfigurationChanged=$false; modelDownloadAttempted=$false }
    Write-NewJson $reportPath $report
    return [pscustomobject]@{ javaReady=[bool]$java.ready; javaHome=$java.javaHome; localAvailable=[bool]$local.available; localModel=$local.model; issues=$issues.ToArray(); reportPath=(ConvertTo-AutomationEnvironmentEvidencePath $Root $reportPath) }
}

function Invoke-AutomationLocalAdmission {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Root, [Parameter(Mandatory=$true)]$Config, [Parameter(Mandatory=$true)][string]$Model, [Parameter(Mandatory=$true)][string]$RunDirectory, [string]$CodexCommand='codex')
    $directory=Get-AutomationEnvironmentDirectory $Root $RunDirectory
    $runRelative=(ConvertTo-AutomationEnvironmentEvidencePath $Root $directory).TrimEnd('/')
    $applicationBefore=Get-SourceSnapshot $Root
    $applicationBefore.files=@($applicationBefore.files | Where-Object { -not $_.path.StartsWith($runRelative + '/', [StringComparison]::OrdinalIgnoreCase) })
    $ledgerBefore=Get-LedgerFingerprint $Root
    $nextStepPath=Resolve-WorkspacePath $Root 'docs/execution/next-step.md'
    $nextStepBefore=if (Test-Path -LiteralPath $nextStepPath) { (Get-FileHash -LiteralPath $nextStepPath -Algorithm SHA256).Hash } else { 'ABSENT' }
    $fixture=Join-Path $directory 'fixture'
    if (Test-Path -LiteralPath $fixture) { throw 'Admission fixture already exists; use a fresh run directory.' }
    [void][IO.Directory]::CreateDirectory($fixture)
    $issues=New-Object 'System.Collections.Generic.List[string]'
    $admitted=$false
    $evidence=New-Object 'System.Collections.Generic.List[string]'
    $first=$null; $second=$null; $baseline=$null; $after=$null
    $reportPath=Join-Path $directory 'admission-report.json'
    try {
        $node=Get-AutomationEnvironmentCommand 'node'
        if (-not $node) { throw 'Node is missing; independent synthetic checks cannot run.' }
        $marker=[Guid]::NewGuid().ToString('N')
        Write-NewUtf8 (Join-Path $fixture 'AGENTS.md') 'Synthetic model admission only. Edit capacity.js alone. Tests, marker and this contract are immutable. Never touch parent application files or services. No installs, Git changes, network requests or model changes. Tool-output evidence may be written only below docs/execution/runs/.'
        Write-NewUtf8 (Join-Path $fixture 'fixture-marker.txt') $marker
        Write-NewUtf8 (Join-Path $fixture 'capacity.js') "function availableSeats(capacity, held, confirmed) { return capacity - confirmed; }`nmodule.exports = { availableSeats };`n"
        $test=@'
const assert = require('node:assert/strict');
const { availableSeats } = require('./capacity');
let passed = 0;
let failed = 0;
const cases = [
  ['held seats are allocated', () => assert.equal(availableSeats(12, 3, 4), 5)],
  ['fully confirmed session', () => assert.equal(availableSeats(12, 0, 12), 0)],
  ['available seats cannot be negative', () => assert.equal(availableSeats(12, 4, 10), 0)],
  ['negative capacity', () => assert.throws(() => availableSeats(-1, 0, 0), RangeError)],
  ['negative held seats', () => assert.throws(() => availableSeats(10, -1, 0), RangeError)],
  ['negative confirmed seats', () => assert.throws(() => availableSeats(10, 0, -1), RangeError)],
  ['fractional capacity', () => assert.throws(() => availableSeats(3.5, 0, 0), RangeError)],
  ['NaN held seats', () => assert.throws(() => availableSeats(10, NaN, 0), RangeError)],
  ['infinite confirmed seats', () => assert.throws(() => availableSeats(10, 0, Infinity), RangeError)],
  ['string capacity', () => assert.throws(() => availableSeats('10', 0, 0), RangeError)]
];
for (const [name, test] of cases) {
  try { test(); passed++; console.log('PASS ' + name); }
  catch (error) { failed++; console.error('FAIL ' + name + ': ' + error.message); }
}
console.log(JSON.stringify({ passed, failed, total: cases.length }));
process.exitCode = failed === 0 && passed === 10 ? 0 : 1;
'@
        Write-NewUtf8 (Join-Path $fixture 'capacity.test.js') $test
        $schemaPath=Resolve-WorkspacePath $Root 'contracts/local-result.schema.json' -MustExist
        $testHash=(Get-FileHash -LiteralPath (Join-Path $fixture 'capacity.test.js') -Algorithm SHA256).Hash
        $before=Get-SourceSnapshot $fixture
        $baseline=Invoke-AutomationEnvironmentNative $node @((Join-Path $fixture 'capacity.test.js')) $directory 30
        Write-NewUtf8 (Join-Path $directory 'baseline-test.log') ($baseline.output + "`n" + $baseline.errorOutput)
        if ($baseline.exitCode -ne 1 -or ($baseline.output + $baseline.errorOutput) -notmatch '"total":10' -or ($baseline.output + $baseline.errorOutput) -match '"failed":0') { throw 'Synthetic failing baseline did not execute all ten independent checks.' }
        $timeout=[int](Get-AutomationEnvironmentOption $Config 'localTrialTimeoutSeconds' 180)
        $sandbox=[string](Get-AutomationEnvironmentOption $Config 'windowsSandbox' 'mxc')
        $repairDirectory=Join-Path $fixture 'docs/execution/runs/repair'
        $prompt=@'
This is isolated local-model admission, not application task T01. Read AGENTS.md, fixture-marker.txt, capacity.js and capacity.test.js using tools. Repair capacity.js only. availableSeats must validate every argument as a nonnegative safe integer, throw RangeError otherwise, subtract held and confirmed seats, and clamp to zero. Preserve the test byte-for-byte and every other source file. Run node capacity.test.js; record its actual output in docs/execution/runs/repair/tests.log. Do not install or call network/Git/services. Return JSON matching the supplied local-result schema, taskId T00, revision CAPTURED_BY_WRAPPER, status NEEDS_REVIEW only if the ten checks really pass; otherwise FAILED/BLOCKED. Summary must contain REPAIR_PROOF: followed by the exact value read from fixture-marker.txt. changedFiles must be ["capacity.js"]. Include actual node exit code and docs/execution/runs/repair/tests.log evidence. Tooling time is bounded; do not claim success from intent.
'@
        $first=Invoke-AutomationAgent -Root $fixture -Role Admission -Model $Model -Provider lmstudio -Prompt $prompt -SchemaPath $schemaPath -RunDirectory $repairDirectory -MaxRunSeconds $timeout -WindowsSandbox $sandbox -CodexCommand $CodexCommand
        if (-not $first.valid -or $null -eq $first.result -or $first.result.status -ne 'NEEDS_REVIEW') { throw 'Repair invocation did not produce a valid review candidate.' }
        Assert-ResultShape $first.result 'Local' 'T00'
        if ($first.result.revision -cne 'CAPTURED_BY_WRAPPER' -or @($first.result.changedFiles).Count -ne 1 -or $first.result.changedFiles[0] -cne 'capacity.js') { throw 'Repair structured handoff has an invalid revision or changed-file declaration.' }
        foreach ($check in @($first.result.checks)) {
            foreach ($path in @($check.evidencePaths)) { [void](Resolve-WorkspacePath $fixture $path -MustExist) }
        }
        if ($first.result.summary -notmatch [regex]::Escape('REPAIR_PROOF:' + $marker)) { throw 'Repair did not prove reading the isolated marker.' }
        $postRepair=Get-SourceSnapshot $fixture
        $changed=@(Get-ChangedSourcePaths $before $postRepair)
        if ($changed.Count -ne 1 -or $changed[0] -cne 'capacity.js') { throw ('Repair changed forbidden source paths or made no repair: ' + ($changed -join ', ')) }
        if ((Get-FileHash -LiteralPath (Join-Path $fixture 'capacity.test.js') -Algorithm SHA256).Hash -cne $testHash) { throw 'Admission test was modified; admission rejected.' }
        $after=Invoke-AutomationEnvironmentNative $node @((Join-Path $fixture 'capacity.test.js')) $directory 30
        $afterText=$after.output + "`n" + $after.errorOutput
        Write-NewUtf8 (Join-Path $directory 'after-test.log') $afterText
        if ($after.exitCode -ne 0 -or $afterText -notmatch '"passed":10,"failed":0,"total":10') { throw 'Independent immutable ten-case verification failed.' }
        # A second session receives no marker value in its prompt and must re-read persisted files.
        Write-NewUtf8 (Join-Path $fixture 'checks/after-test.log') $afterText
        $beforeContinuation=Get-SourceSnapshot $fixture
        $continuationPrompt=@'
Read-only continuation of synthetic admission. Read AGENTS.md, fixture-marker.txt, capacity.js and capacity.test.js from disk with tools; do not edit or create any file. Re-run node capacity.test.js. Return local-result JSON taskId T00, revision CAPTURED_BY_WRAPPER, status NEEDS_REVIEW only on a real zero exit; changedFiles []; checks contains the real command/exitCode and existing evidence path checks/after-test.log. Summary must contain CONTINUATION_PROOF: followed by the exact fixture-marker.txt value, and AVAILABLE:5 after independently evaluating availableSeats(12,3,4). No application acceptance is claimed.
'@
        $continuationDirectory=Join-Path $fixture 'docs/execution/runs/continuation'
        $second=Invoke-AutomationAgent -Root $fixture -Role Admission -Model $Model -Provider lmstudio -Prompt $continuationPrompt -SchemaPath $schemaPath -RunDirectory $continuationDirectory -MaxRunSeconds $timeout -WindowsSandbox $sandbox -CodexCommand $CodexCommand -ReadOnly
        if (-not $second.valid -or $null -eq $second.result -or $second.result.status -ne 'NEEDS_REVIEW') { throw 'Read-only continuation did not produce valid structured output.' }
        Assert-ResultShape $second.result 'Local' 'T00'
        if ($second.result.revision -cne 'CAPTURED_BY_WRAPPER') { throw 'Continuation revision was not CAPTURED_BY_WRAPPER.' }
        foreach ($check in @($second.result.checks)) {
            foreach ($path in @($check.evidencePaths)) { [void](Resolve-WorkspacePath $fixture $path -MustExist) }
        }
        if ($second.result.summary -notmatch [regex]::Escape('CONTINUATION_PROOF:' + $marker) -or $second.result.summary -notmatch 'AVAILABLE:5') { throw 'Second session did not prove persisted reads and the corrected result.' }
        $afterContinuation=Get-SourceSnapshot $fixture
        if (@(Get-ChangedSourcePaths $beforeContinuation $afterContinuation).Count -ne 0 -or @($second.result.changedFiles).Count -ne 0) { throw 'Read-only continuation modified synthetic source.' }
        if ((Get-FileHash -LiteralPath (Join-Path $fixture 'capacity.test.js') -Algorithm SHA256).Hash -cne $testHash) { throw 'Immutable admission tests changed during continuation.' }
        $admitted=$true
    } catch { $issues.Add($_.Exception.Message) }
    try {
        $applicationAfter=Get-SourceSnapshot $Root
        $applicationAfter.files=@($applicationAfter.files | Where-Object { -not $_.path.StartsWith($runRelative + '/', [StringComparison]::OrdinalIgnoreCase) })
        $applicationChanges=@(Get-ChangedSourcePaths $applicationBefore $applicationAfter)
        $nextStepAfter=if (Test-Path -LiteralPath $nextStepPath) { (Get-FileHash -LiteralPath $nextStepPath -Algorithm SHA256).Hash } else { 'ABSENT' }
        if ($applicationChanges.Count -gt 0 -or (Get-LedgerFingerprint $Root) -cne $ledgerBefore -or $nextStepAfter -cne $nextStepBefore) { $admitted=$false; $issues.Add('Admission changed application source, ledger or handoff outside its isolated owned run; no automatic rollback was attempted.') }
    } catch { $admitted=$false; $issues.Add('Application preservation check failed: ' + $_.Exception.Message) }
    foreach ($path in @((Join-Path $directory 'baseline-test.log'),(Join-Path $directory 'after-test.log'))) {
        if (Test-Path -LiteralPath $path) { $evidence.Add((ConvertTo-AutomationEnvironmentEvidencePath $Root $path)) }
    }
    foreach ($agent in @($first,$second)) {
        if ($null -eq $agent) { continue }
        foreach ($path in @($agent.evidencePaths)) {
            $full=if ([IO.Path]::IsPathRooted($path)) { $path } else { Join-Path $fixture $path }
            if (Test-Path -LiteralPath $full) { $evidence.Add((ConvertTo-AutomationEnvironmentEvidencePath $Root $full)) }
        }
    }
    Write-NewJson $reportPath ([ordered]@{ observedAt=[DateTime]::UtcNow.ToString('o'); model=$Model; admitted=$admitted; fixture=(ConvertTo-AutomationEnvironmentEvidencePath $Root $fixture); baselineExitCode=$(if ($null -ne $baseline) {$baseline.exitCode} else {$null}); independentExitCode=$(if ($null -ne $after) {$after.exitCode} else {$null}); immutableTenCaseTestsRequired=$true; immutableTenCaseTestsVerified=$admitted; readOnlySecondSessionRequired=$true; issues=$issues.ToArray(); evidencePaths=$evidence.ToArray(); applicationAcceptance=$false })
    $evidence.Add((ConvertTo-AutomationEnvironmentEvidencePath $Root $reportPath))
    return [pscustomobject]@{ admitted=$admitted; model=$Model; issues=$issues.ToArray(); evidencePaths=$evidence.ToArray() }
}
