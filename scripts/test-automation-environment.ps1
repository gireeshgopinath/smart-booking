[CmdletBinding()]
param([string]$Root)
$ErrorActionPreference='Stop'
if (-not $Root) { $Root=Split-Path -Parent $PSScriptRoot }
. (Join-Path $PSScriptRoot 'automation-environment.ps1')
$fixture=New-WorkflowDirectory $Root '' 'automation-environment-test'
[void][IO.Directory]::CreateDirectory((Join-Path $fixture 'contracts'))
Copy-Item -LiteralPath (Join-Path $Root 'contracts/local-result.schema.json') -Destination (Join-Path $fixture 'contracts/local-result.schema.json')
$script:originalNative=${function:Invoke-AutomationEnvironmentNative}
$script:originalFind=${function:Find-AutomationJava25}
$script:nodeCommand=(Get-Command node -ErrorAction Stop).Source
$script:testMode='success'
$script:loaded=@()
$script:mutations=New-Object 'System.Collections.Generic.List[string]'
$script:zipMode='checksum'
$script:zipBytes=$null
$checks=New-Object 'System.Collections.Generic.List[object]'
$config=[pscustomobject]@{ localModels=@('qwen3.8-27b','qwen3.8-flash-next'); manageLocalServices=$true; installPrerequisites=$false; modelBusyWaitSeconds=0; localContextLength=32768; localParallel=1; localTrialTimeoutSeconds=10; windowsSandbox='mxc' }

function Assert-EnvironmentTest {
    param([bool]$Condition,[string]$Name)
    if (-not $Condition) { throw ('Environment self-test failed: ' + $Name) }
    $script:checks.Add([pscustomobject]@{ check=$Name; result='PASS' })
}
function New-EnvironmentTestRun {
    param([string]$Name)
    $path=Join-Path $script:fixture $Name
    [void][IO.Directory]::CreateDirectory($path)
    return $path
}
function Get-AutomationEnvironmentCommand {
    param([string]$Name)
    if ($Name -eq 'node') { return $script:nodeCommand }
    if ($Name -eq 'lms') { return 'mock-lms.exe' }
    return $null
}
function Invoke-RestMethod {
    param([string]$Uri,[string]$Method,[int]$TimeoutSec)
    if ($Uri -ne 'http://127.0.0.1:1234/v1/models') { throw 'Mock forbids every non-loopback request.' }
    return [pscustomobject]@{ data=@([pscustomobject]@{id='qwen3.8-27b'},[pscustomobject]@{id='qwen3.8-flash-next'}) }
}
function Invoke-AutomationEnvironmentNative {
    param([string]$Command,[string[]]$Arguments,[string]$RunDirectory,[int]$MaxRunSeconds=30)
    if ($Command -eq $script:nodeCommand) { return (& $script:originalNative @PSBoundParameters) }
    if ($Command -like '*java.exe') {
        $version=if ($script:testMode -eq 'java24') { 'openjdk version "24.0.2"' } else { 'openjdk version "25.0.4"' }
        return [pscustomobject]@{ exitCode=0; timedOut=$false; output=$version; errorOutput=''; directory=$RunDirectory }
    }
    if ($Command -ne 'mock-lms.exe') { throw 'Unexpected native command in environment test.' }
    switch ($Arguments[0]) {
        'ps' { $output=ConvertTo-Json -InputObject @($script:loaded) -Depth 5 -Compress }
        'ls' { $output=ConvertTo-Json -InputObject @([pscustomobject]@{type='llm';modelKey='qwen3.8-27b'},[pscustomobject]@{type='llm';modelKey='qwen3.8-flash-next'}) -Compress }
        'unload' { $script:mutations.Add('unload:' + $Arguments[1]); $script:loaded=@($script:loaded | Where-Object {$_.identifier -ne $Arguments[1]}); $output='unloaded' }
        'load' { $script:mutations.Add('load:' + $Arguments[1]); $script:loaded=@([pscustomobject]@{type='llm';modelKey=$Arguments[1];identifier=$Arguments[1];status='idle';queued=0;contextLength=32768;parallel=1}); $output='loaded' }
        default { throw 'Unexpected LM Studio command in test.' }
    }
    return [pscustomobject]@{ exitCode=0; timedOut=$false; output=$output; errorOutput=''; directory=$RunDirectory }
}
function Invoke-AutomationAgent {
    param([string]$Root,[string]$Role,[string]$Model,[string]$Provider,[string]$Prompt,[string]$SchemaPath,[string]$RunDirectory,[int]$MaxRunSeconds,[string]$WindowsSandbox,[string]$CodexCommand,[switch]$ReadOnly)
    [void][IO.Directory]::CreateDirectory($RunDirectory)
    $marker=[IO.File]::ReadAllText((Join-Path $Root 'fixture-marker.txt'))
    if ($ReadOnly -and $script:testMode -eq 'continuation-failure') { return [pscustomobject]@{valid=$false;result=$null;issues=@('synthetic continuation rejection');evidencePaths=@()} }
    if (-not $ReadOnly -and $script:testMode -ne 'no-edit') {
        [IO.File]::WriteAllText((Join-Path $Root 'capacity.js'),"function availableSeats(capacity, held, confirmed) { for (const v of [capacity, held, confirmed]) { if (!Number.isSafeInteger(v) || v < 0) throw new RangeError('invalid'); } return Math.max(0, capacity - held - confirmed); }`nmodule.exports = { availableSeats };`n")
    }
    if ($script:testMode -eq 'tamper-test' -and -not $ReadOnly) { [IO.File]::WriteAllText((Join-Path $Root 'capacity.test.js'),'process.exitCode=0;') }
    if ($script:testMode -eq 'extra-edit' -and -not $ReadOnly) { [IO.File]::WriteAllText((Join-Path $Root 'unexpected.txt'),'forbidden') }
    if ($script:testMode -eq 'parent-write' -and -not $ReadOnly) { [IO.File]::WriteAllText((Join-Path $script:fixture 'protected.txt'),'forbidden parent mutation') }
    if ($script:testMode -eq 'continuation-write' -and $ReadOnly) { [IO.File]::WriteAllText((Join-Path $Root 'capacity.js'),'module.exports={availableSeats:()=>5};') }
    $summary=if ($ReadOnly) {'CONTINUATION_PROOF:' + $marker + ';AVAILABLE:5'} else {'REPAIR_PROOF:' + $marker}
    if ($script:testMode -eq 'false-proof') { $summary='No marker was read.' }
    $checkEvidence=if ($ReadOnly) { 'checks/after-test.log' } else { 'docs/execution/runs/repair/tests.log' }
    if (-not $ReadOnly -and $script:testMode -ne 'missing-evidence') { Write-NewUtf8 (Join-Path $Root $checkEvidence) 'Synthetic mocked-agent evidence; independent supervisor tests run with real Node.' }
    $result=[pscustomobject]@{taskId='T00';status='NEEDS_REVIEW';revision='CAPTURED_BY_WRAPPER';summary=$summary;changedFiles=@();checks=@([pscustomobject]@{command='node capacity.test.js';exitCode=0;evidencePaths=@($checkEvidence)});risks=@('MOCK AGENT; independent fixture tests remain real');blockedReason=$null}
    if (-not $ReadOnly) { $result.changedFiles=@('capacity.js') }
    if ($script:testMode -eq 'bad-json-shape' -and -not $ReadOnly) { $result.status='PASS' }
    Write-NewJson (Join-Path $RunDirectory 'result.json') $result
    return [pscustomobject]@{valid=$true;result=$result;issues=@();evidencePaths=@((Join-Path $RunDirectory 'result.json'))}
}

# No external service, model or operating-system configuration is changed by these tests.
$script:loaded=@([pscustomobject]@{type='llm';modelKey='qwen3.8-flash-next';identifier='qwen3.8-flash-next';status='generating';queued=0;contextLength=262144;parallel=4})
$script:mutations.Clear()
$local=Initialize-AutomationLocalModel $config (New-EnvironmentTestRun 'busy')
Assert-EnvironmentTest (-not $local.available -and $script:mutations.Count -eq 0 -and $local.issues[0] -match 'active') 'active unrelated generation is preserved and unavailable'
$script:loaded=@([pscustomobject]@{type='llm';modelKey='qwen3.8-flash-next';identifier='qwen3.8-flash-next';status='idle';queued=2;contextLength=262144;parallel=4})
$local=Initialize-AutomationLocalModel $config (New-EnvironmentTestRun 'queued')
Assert-EnvironmentTest (-not $local.available -and $script:mutations.Count -eq 0) 'queued unrelated generation is preserved'
$script:loaded=@([pscustomobject]@{type='llm';modelKey='qwen3.8-flash-next';identifier='qwen3.8-flash-next';status='unknown';queued=0;contextLength=262144;parallel=4})
$local=Initialize-AutomationLocalModel $config (New-EnvironmentTestRun 'unknown')
Assert-EnvironmentTest (-not $local.available -and $script:mutations.Count -eq 0) 'unknown local activity fails closed'
$script:loaded=@([pscustomobject]@{type='llm';modelKey='qwen3.8-flash-next';identifier='qwen3.8-flash-next';status='idle';queued=0;contextLength=262144;parallel=4})
$local=Initialize-AutomationLocalModel $config (New-EnvironmentTestRun 'idle-selection')
Assert-EnvironmentTest ($local.available -and $local.model -eq 'qwen3.8-27b' -and ($script:mutations -join ',') -eq 'unload:qwen3.8-flash-next,load:qwen3.8-27b') 'idle installed model switch uses bounded context and one prediction'
$unmanaged=$config | ConvertTo-Json | ConvertFrom-Json
$unmanaged.manageLocalServices=$false
$script:loaded=@()
$script:mutations.Clear()
$local=Initialize-AutomationLocalModel $unmanaged (New-EnvironmentTestRun 'unmanaged')
Assert-EnvironmentTest (-not $local.available -and $script:mutations.Count -eq 0) 'disabled service management never loads a model'

$fakeJava=Join-Path $fixture 'java/bin/java.exe'
Write-NewUtf8 $fakeJava 'not an executable; native version probe is mocked'
function Get-AutomationJavaCandidates { param([string]$Root) return @($script:fakeJava) }
$script:testMode='success'
$java=Find-AutomationJava25 $fixture (New-EnvironmentTestRun 'java25')
Assert-EnvironmentTest ($java.ready) 'existing Java 25 is detected through a bounded version probe'
$script:testMode='java24'
$java=Find-AutomationJava25 $fixture (New-EnvironmentTestRun 'java24')
Assert-EnvironmentTest (-not $java.ready) 'Java 24 cannot satisfy Java 25 prerequisite'

function Get-AutomationJdkMetadata {
    if ($script:zipMode -eq 'traversal') {
        $hash=[Security.Cryptography.SHA256]::Create()
        try { $checksum=[BitConverter]::ToString($hash.ComputeHash($script:zipBytes)).Replace('-','').ToLowerInvariant() } finally { $hash.Dispose() }
        return [pscustomobject]@{metadataUrl='MOCK';link='MOCK';sha256=$checksum;size=$script:zipBytes.Length;release='MOCK';version='25'}
    }
    return [pscustomobject]@{metadataUrl='MOCK';link='MOCK';sha256=('0' * 64);size=7;release='MOCK';version='25'}
}
function Invoke-AutomationJdkDownload {
    param($Metadata,[string]$ArchivePath,[string]$RunDirectory)
    if ($script:zipMode -eq 'traversal') { [IO.File]::WriteAllBytes($ArchivePath,$script:zipBytes) } else { Write-NewUtf8 $ArchivePath 'bad-zip' }
}
$rejected=$false
try { Install-AutomationPortableJava25 $fixture (New-EnvironmentTestRun 'checksum') | Out-Null } catch { $rejected=$_.Exception.Message -match 'checksum mismatch' }
Assert-EnvironmentTest $rejected 'portable JDK checksum mismatch rejects extraction'
Assert-EnvironmentTest (@(Get-ChildItem -LiteralPath (Join-Path $fixture '.tools/jdk25') -Directory).Count -eq 0) 'unverified JDK archive is never extracted'

Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
$memory=New-Object IO.MemoryStream
$zip=New-Object IO.Compression.ZipArchive($memory,[IO.Compression.ZipArchiveMode]::Create,$true)
$entry=$zip.CreateEntry('../escape.txt')
$entryStream=$entry.Open()
$bytes=[Text.Encoding]::UTF8.GetBytes('unsafe path')
$entryStream.Write($bytes,0,$bytes.Length)
$entryStream.Dispose()
$zip.Dispose()
$script:zipBytes=$memory.ToArray()
$memory.Dispose()
$script:zipMode='traversal'
$rejected=$false
try { Install-AutomationPortableJava25 $fixture (New-EnvironmentTestRun 'zip-traversal') | Out-Null } catch { $rejected=$_.Exception.Message -match 'escapes extraction directory' }
Assert-EnvironmentTest $rejected 'checksum-valid JDK ZIP traversal is rejected before extraction'

$junctionTarget=New-EnvironmentTestRun 'junction-target'
$junctionPath=Join-Path $fixture 'linked'
New-Item -ItemType Junction -Path $junctionPath -Target $junctionTarget | Out-Null
$rejected=$false
try { Get-AutomationEnvironmentDirectory $fixture (Join-Path $junctionPath 'evidence') | Out-Null } catch { $rejected=$_.Exception.Message -match 'reparse-point ancestor' }
Assert-EnvironmentTest $rejected 'evidence path with a junction ancestor is rejected'

foreach ($mode in @('success','no-edit','tamper-test','extra-edit','false-proof','bad-json-shape','missing-evidence','continuation-failure','continuation-write','parent-write')) {
    $script:testMode=$mode
    $result=Invoke-AutomationLocalAdmission -Root $fixture -Config $config -Model 'mock-local-model' -RunDirectory (New-EnvironmentTestRun ('admission-' + $mode)) -CodexCommand 'mock-only'
    if ($mode -eq 'success') {
        Assert-EnvironmentTest ($result.admitted -and $result.issues.Count -eq 0) 'admission requires real ten-case tests and valid second-session proof'
    } else {
        Assert-EnvironmentTest (-not $result.admitted -and $result.issues.Count -gt 0) ('admission rejects ' + $mode)
    }
}
$report=[ordered]@{valid=$true;fixtureDirectory=$fixture;powershell=$PSVersionTable.PSVersion.ToString();checks=$checks.ToArray();liveModels='NOT_RUN';network='MOCKED';applicationTests='NOT_RUN';ledgersChanged=$false}
Write-NewJson (Join-Path $fixture 'self-test-summary.json') $report
$report | ConvertTo-Json -Depth 12
