[CmdletBinding()]
param([string]$Root)
$ErrorActionPreference='Stop'
if (-not $Root) { $Root=Split-Path -Parent $PSScriptRoot }
. (Join-Path $PSScriptRoot 'automation-core.ps1')
$fixture=New-WorkflowDirectory $Root '' 'automation-core-test'
$template=Join-Path $fixture 'template with spaces'
[void][IO.Directory]::CreateDirectory($template)
$checks=New-Object 'System.Collections.Generic.List[object]'
foreach ($schema in @('local-result.schema.json','review-result.schema.json')) {
    [void][IO.Directory]::CreateDirectory((Join-Path $template 'contracts'))
    Copy-Item -LiteralPath (Join-Path $Root ('contracts/' + $schema)) -Destination (Join-Path $template ('contracts/' + $schema))
}
Write-NewUtf8 (Join-Path $template 'AGENTS.md') 'Synthetic process-helper tests only. No model, application task or product acceptance.'
Write-NewJson (Join-Path $template 'contracts/tasks.json') ([ordered]@{tasks=@([ordered]@{id='T00';title='Synthetic helper fixture';dependencies=@();specPath='docs/features/T00.md'})})
Write-NewUtf8 (Join-Path $template 'docs/features/T00.md') 'Immutable synthetic task specification.'
Write-NewUtf8 (Join-Path $template 'docs/execution/task-ledger.json') '{"tasks":[]}'
Write-NewUtf8 (Join-Path $template 'docs/execution/task-ledger.md') 'Synthetic immutable ledger.'
Write-NewUtf8 (Join-Path $template 'docs/execution/next-step.md') 'Synthetic immutable handoff.'
Write-NewUtf8 (Join-Path $template 'design.txt') 'Synthetic immutable source plan.'
Write-NewJson (Join-Path $template 'docs/sources/source-manifest.json') ([ordered]@{sources=@([ordered]@{path='design.txt'})})
Write-NewUtf8 (Join-Path $template 'src/allowed.txt') 'before allowed'
Write-NewUtf8 (Join-Path $template 'src/unrelated.txt') 'before unrelated'
Write-NewUtf8 (Join-Path $template 'docs/verification/T00/mock-check.txt') 'Mock CLI evidence only; never application acceptance.'

$mock=@'
$ErrorActionPreference='Stop'
$invocation=@($args)
if ($invocation.Count -eq 1 -and $invocation[0] -eq '--version') { 'codex-cli MOCK PROCESS TEST'; exit 0 }
if ($invocation.Count -eq 2 -and $invocation[1] -eq '--help') { '--output-schema --output-last-message --sandbox --ignore-user-config --oss --local-provider --json'; exit 0 }
$prompt=$input | Out-String
$rootPath=$invocation[[Array]::IndexOf($invocation,'--cd') + 1]
$resultPath=$invocation[[Array]::IndexOf($invocation,'--output-last-message') + 1]
$runDirectory=Split-Path -Parent $resultPath
$modelIndex=[Array]::IndexOf($invocation,'--model')
$mode=if ($modelIndex -ge 0) { $invocation[$modelIndex+1] } else { 'mock-default' }
[IO.File]::WriteAllText((Join-Path $runDirectory 'received.json'),([ordered]@{arguments=$invocation;prompt=$prompt;workingDirectory=(Get-Location).Path} | ConvertTo-Json -Depth 8))
if ($mode -eq 'mock-timeout') {
    $childScript=Join-Path $runDirectory 'owned-descendant.ps1'
    [IO.File]::WriteAllText($childScript,'Start-Sleep -Seconds 45')
    $hostExecutable=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $child=Start-Process -FilePath $hostExecutable -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-File',('"' + $childScript + '"')) -WindowStyle Hidden -PassThru
    [IO.File]::WriteAllText((Join-Path $runDirectory 'descendant.pid'),[string]$child.Id)
    Start-Sleep -Seconds 45
    exit 0
}
if ($mode -eq 'mock-missing-result') { 'Intentionally no result.'; exit 0 }
if ($mode -eq 'mock-malformed-json') { [IO.File]::WriteAllText($resultPath,'{ malformed JSON'); exit 0 }
switch ($mode) {
    'mock-allowed-edit' { [IO.File]::WriteAllText((Join-Path $rootPath 'src/allowed.txt'),'after allowed') }
    'mock-out-of-scope' { [IO.File]::WriteAllText((Join-Path $rootPath 'src/unrelated.txt'),'after unrelated') }
    'mock-protected' { [IO.File]::WriteAllText((Join-Path $rootPath 'AGENTS.md'),'forbidden protected edit') }
    'mock-protected-plan' { [IO.File]::WriteAllText((Join-Path $rootPath 'design.txt'),'forbidden source-plan edit') }
    'mock-protected-new' { [IO.File]::WriteAllText((Join-Path $rootPath 'scripts/automation-core.ps1'),'forbidden creation of protected file') }
    'mock-ledger' { [IO.File]::WriteAllText((Join-Path $rootPath 'docs/execution/task-ledger.md'),'forbidden ledger edit') }
}
$result=[ordered]@{taskId='T00';status='NEEDS_REVIEW';revision='CAPTURED_BY_WRAPPER';summary='Synthetic mock process transport result';changedFiles=@();checks=@([ordered]@{command='synthetic fixture only';exitCode=0;evidencePaths=@('docs/verification/T00/mock-check.txt')});risks=@('MOCK CLI: no real model or application behavior tested');blockedReason=$null}
if ($mode -eq 'mock-invalid-enum') { $result.status='PASS' }
if ($mode -eq 'mock-extra-property') { $result.unexpected='schema violation' }
if ($mode -eq 'mock-invalid-type') { $result.checks[0].exitCode='zero' }
[IO.File]::WriteAllText($resultPath,($result | ConvertTo-Json -Depth 10))
'Mock process received stdin and emitted structured output.'
if ($mode -eq 'mock-nonzero') { [Console]::Error.WriteLine('intentional mock exit'); exit 9 }
exit 0
'@
Write-NewUtf8 (Join-Path $template 'scripts/mock-codex.ps1') $mock
$command=@'
param([string]$Mode,[Parameter(ValueFromRemainingArguments=$true)][string[]]$Values)
$ErrorActionPreference='Stop'
if ($Mode -eq 'throw') { throw 'intentional synthetic command failure' }
if ($Mode -eq 'exit-seven') { [Console]::Error.WriteLine('intentional synthetic exit 7'); exit 7 }
if ($Mode -eq 'timeout') { Start-Sleep -Seconds 45; exit 0 }
[ordered]@{values=@($Values);workingDirectory=(Get-Location).Path} | ConvertTo-Json -Depth 8 -Compress
exit 0
'@
Write-NewUtf8 (Join-Path $template 'scripts/mock-command.ps1') $command

function Assert-CoreTest {
    param([bool]$Condition,[string]$Name)
    if (-not $Condition) { throw ('Automation core self-test failed: ' + $Name) }
    $script:checks.Add([pscustomobject]@{check=$Name;result='PASS'})
}
function New-CoreTestRoot {
    param([string]$Name)
    $path=Join-Path $script:fixture ($Name + ' with spaces')
    [void][IO.Directory]::CreateDirectory($path)
    foreach ($item in @(Get-ChildItem -LiteralPath $script:template -Force)) { Copy-Item -LiteralPath $item.FullName -Destination $path -Recurse }
    return $path
}
function Invoke-CoreMockAgent {
    param([string]$Scenario,[string]$Model,[switch]$ReadOnly,[string[]]$AllowedPaths=@('src/allowed.txt'))
    $project=New-CoreTestRoot $Scenario
    $directory=Join-Path $project 'docs/execution/runs/agent'
    $prompt="Synthetic process prompt with a second line.`nLiteral dollar text: `$(never_execute) and a quoted value: `"preserve me`"."
    $result=Invoke-AutomationAgent -Root $project -Role Admission -Model $Model -Prompt $prompt -SchemaPath (Join-Path $project 'contracts/local-result.schema.json') -RunDirectory $directory -MaxRunSeconds 15 -WindowsSandbox mxc -CodexCommand (Join-Path $project 'scripts/mock-codex.ps1') -ReadOnly:$ReadOnly -AllowedPaths $AllowedPaths
    return [pscustomobject]@{project=$project;directory=$directory;prompt=$prompt;result=$result}
}

$project=New-CoreTestRoot 'command arguments'
$arguments=@('a value with spaces','literal"quotes"','$(never_execute)','back`tick','a;b','C:\synthetic\path')
$commandResult=Invoke-AutomationCommand -Root $project -Command (Join-Path $project 'scripts/mock-command.ps1') -Arguments (@('echo') + $arguments) -RunDirectory (Join-Path $project 'docs/execution/runs/command-echo') -MaxRunSeconds 15
$received=Read-WorkflowJson $commandResult.stdoutPath
Assert-CoreTest ($commandResult.exitCode -eq 0 -and $received.workingDirectory -ceq $project -and (($received.values | ConvertTo-Json -Compress) -ceq ($arguments | ConvertTo-Json -Compress))) 'command child preserves literal arguments and working directory'
$failed=Invoke-AutomationCommand -Root $project -Command (Join-Path $project 'scripts/mock-command.ps1') -Arguments @('exit-seven') -RunDirectory (Join-Path $project 'docs/execution/runs/command-exit') -MaxRunSeconds 15
Assert-CoreTest ($failed.exitCode -eq 7 -and -not $failed.timedOut) 'command child preserves nonzero native exit code'
$thrown=Invoke-AutomationCommand -Root $project -Command (Join-Path $project 'scripts/mock-command.ps1') -Arguments @('throw') -RunDirectory (Join-Path $project 'docs/execution/runs/command-throw') -MaxRunSeconds 15
Assert-CoreTest ($thrown.exitCode -ne 0) 'command child rejects PowerShell exception'

$case=Invoke-CoreMockAgent 'valid transport' 'mock-valid space "quoted"'
$received=Read-WorkflowJson (Join-Path $case.directory 'received.json')
$modelIndex=[Array]::IndexOf(@($received.arguments),'--model')
$sandboxIndex=[Array]::IndexOf(@($received.arguments),'--sandbox')
Assert-CoreTest ($case.result.valid -and $case.result.result.taskId -eq 'T00') 'agent actual child transport accepts schema-valid structured result'
Assert-CoreTest ($modelIndex -ge 0 -and $received.arguments[$modelIndex+1] -ceq 'mock-valid space "quoted"' -and $sandboxIndex -ge 0 -and $received.arguments[$sandboxIndex+1] -eq 'workspace-write' -and $received.prompt.TrimEnd() -ceq $case.prompt.TrimEnd() -and @($received.arguments) -contains 'model_provider="booking-long-running"' -and @($received.arguments) -contains 'model_providers.booking-long-running.stream_idle_timeout_ms=1800000' -and @($received.arguments) -contains 'model_providers.booking-long-running.stream_max_retries=10' -and @($received.arguments) -contains 'model_providers.booking-long-running.requires_openai_auth=true') 'agent preserves model/stdin and passes longer stream limits with signed-in OpenAI authentication'
$case=Invoke-CoreMockAgent 'configured cloud default' ''
$received=Read-WorkflowJson (Join-Path $case.directory 'received.json')
Assert-CoreTest ($case.result.valid -and @($received.arguments) -notcontains '--model' -and @($received.arguments) -contains 'model_provider="booking-long-running"') 'cloud default omits invented model ID and selects the tuned OpenAI provider'
foreach ($mode in @('mock-nonzero','mock-missing-result','mock-malformed-json','mock-invalid-enum','mock-extra-property','mock-invalid-type')) {
    $case=Invoke-CoreMockAgent $mode $mode
    Assert-CoreTest (-not $case.result.valid -and $case.result.issues.Count -gt 0 -and (Test-Path -LiteralPath $case.result.runSummaryPath)) ('agent rejects ' + $mode + ' and preserves summary')
    if ($mode -eq 'mock-nonzero') {
        $summary=Read-WorkflowJson $case.result.runSummaryPath
        Assert-CoreTest ($summary.process.exitCode -eq 9) 'agent summary preserves actual CLI exit 9'
    }
}
$case=Invoke-CoreMockAgent 'allowed edit' 'mock-allowed-edit'
Assert-CoreTest ($case.result.valid -and $case.result.sourceRevisionBefore -cne $case.result.sourceRevisionAfter -and @($case.result.changedSourcePaths).Count -eq 1 -and $case.result.changedSourcePaths[0] -ceq 'src/allowed.txt') 'agent records allowed source edit and exact new fingerprint'
$case=Invoke-CoreMockAgent 'out of scope' 'mock-out-of-scope'
Assert-CoreTest (-not $case.result.valid -and @($case.result.issues | Where-Object {$_ -match 'Out-of-scope'}).Count -gt 0) 'agent rejects out-of-scope write'
foreach ($mode in @('mock-protected','mock-protected-plan','mock-protected-new')) {
    $case=Invoke-CoreMockAgent $mode $mode -AllowedPaths @('*')
    Assert-CoreTest (-not $case.result.valid -and @($case.result.issues | Where-Object {$_ -match 'Protected'}).Count -gt 0) ('agent rejects protected edit/creation: ' + $mode)
}
$case=Invoke-CoreMockAgent 'read only edit' 'mock-allowed-edit' -ReadOnly
Assert-CoreTest (-not $case.result.valid -and @($case.result.issues | Where-Object {$_ -match 'Read-only'}).Count -gt 0) 'read-only agent source mutation is rejected'
$case=Invoke-CoreMockAgent 'read only ledger' 'mock-ledger' -ReadOnly -AllowedPaths @('*')
Assert-CoreTest (-not $case.result.valid -and @($case.result.issues | Where-Object {$_ -match 'Protected'}).Count -gt 0) 'read-only ledger mutation is detected despite snapshot exclusions'

# The sentinel is owned by this test but unrelated to the invocation tree. It must survive.
$hostExecutable=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$sentinelScript=Join-Path $fixture 'sentinel.ps1'
Write-NewUtf8 $sentinelScript 'Start-Sleep -Seconds 45'
$sentinel=Start-Process -FilePath $hostExecutable -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-File',('"' + $sentinelScript + '"')) -WindowStyle Hidden -PassThru
try {
    $commandTimeout=Invoke-AutomationCommand -Root $project -Command (Join-Path $project 'scripts/mock-command.ps1') -Arguments @('timeout') -RunDirectory (Join-Path $project 'docs/execution/runs/command-timeout') -MaxRunSeconds 2
    $sentinel.Refresh()
    Assert-CoreTest ($commandTimeout.exitCode -eq 124 -and $commandTimeout.timedOut -and -not $sentinel.HasExited) 'command owned deadline captures timeout 124 and preserves unrelated process'
    $project=New-CoreTestRoot 'timeout owned child'
    $directory=Join-Path $project 'docs/execution/runs/timeout'
    $result=Invoke-AutomationAgent -Root $project -Role Admission -Model 'mock-timeout' -Prompt 'Synthetic owned timeout only.' -SchemaPath (Join-Path $project 'contracts/local-result.schema.json') -RunDirectory $directory -MaxRunSeconds 5 -CodexCommand (Join-Path $project 'scripts/mock-codex.ps1')
    $summary=Read-WorkflowJson $result.runSummaryPath
    Assert-CoreTest (-not $result.valid -and $summary.process.timedOut -and $summary.process.exitCode -eq 124) 'agent owned deadline produces timeout 124 with durable summary'
    $pidPath=Join-Path $directory 'descendant.pid'
    Assert-CoreTest (Test-Path -LiteralPath $pidPath) 'timeout fixture actually started an owned descendant'
    $descendantId=[int][IO.File]::ReadAllText($pidPath)
    $descendant=Get-Process -Id $descendantId -ErrorAction SilentlyContinue
    $sentinel.Refresh()
    Assert-CoreTest ($null -eq $descendant -and -not $sentinel.HasExited) 'timeout stops owned descendants and preserves unrelated process'
} finally {
    $sentinel.Refresh()
    if (-not $sentinel.HasExited) { $sentinel.Kill(); [void]$sentinel.WaitForExit(10000) }
    $sentinel.Dispose()
}
$report=[ordered]@{valid=$true;powershell=$PSVersionTable.PSVersion.ToString();fixtureDirectory=$fixture;checks=$checks.ToArray();processes='ACTUAL owned PowerShell processes';provider='MOCK CODEX CLI; no live model or network';applicationTests='NOT_RUN';applicationLedgerChanged=$false}
Write-NewJson (Join-Path $fixture 'self-test-summary.json') $report
$report | ConvertTo-Json -Depth 12
