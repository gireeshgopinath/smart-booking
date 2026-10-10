[CmdletBinding()]
param([string]$Root, [string]$OutputDirectory)
$ErrorActionPreference='Stop'
$automationWorkspace=if ($Root) {[IO.Path]::GetFullPath($Root)} else {Split-Path -Parent $PSScriptRoot}
$testScriptDirectory=$PSScriptRoot
$testHostVersion=$PSVersionTable.PSVersion.ToString()
$productionLedgerBefore=@{}
foreach ($ledgerView in @('docs/execution/task-ledger.json','docs/execution/task-ledger.md')) {
    $productionLedgerBefore[$ledgerView]=(Get-FileHash -LiteralPath (Join-Path $automationWorkspace $ledgerView) -Algorithm SHA256).Hash
}
if (-not $OutputDirectory) {$OutputDirectory='docs/execution/runs/controller-selftest-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8)}
$testOutput=[IO.Path]::GetFullPath((Join-Path $automationWorkspace $OutputDirectory))
$workspacePrefix=$automationWorkspace.TrimEnd([char[]]'\/')+[IO.Path]::DirectorySeparatorChar
if (-not $testOutput.StartsWith($workspacePrefix,[StringComparison]::OrdinalIgnoreCase) -or $OutputDirectory.Replace('\','/') -notmatch '^docs/execution/runs/') {throw 'Self-test output must be a fresh ignored workspace run directory.'}
if (Test-Path -LiteralPath $testOutput) {throw 'Refusing to overwrite self-test evidence.'}
[void][IO.Directory]::CreateDirectory($testOutput)
$script:caseResults=New-Object 'System.Collections.Generic.List[object]'
$script:mockEvents=New-Object 'System.Collections.Generic.List[object]'
$script:mockMode='success'
$script:mockImplementations=0
$script:mockFixtureCount=0

function Write-ControllerFixtureText {
    param([string]$Path,[string]$Text)
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false)))
}
function Write-ControllerFixtureJson {param([string]$Path,$Value) Write-ControllerFixtureText $Path ($Value | ConvertTo-Json -Depth 35)}
function New-ControllerFixture {
    param([string]$Name,[string[]]$TaskIds=@('T01','T02'))
    $script:mockFixtureCount++
    $fixture=Join-Path $testOutput ($script:mockFixtureCount.ToString('00')+'-'+$Name)
    [void][IO.Directory]::CreateDirectory($fixture)
    foreach ($schema in @('local-result.schema.json','review-result.schema.json','automation-plan.schema.json','automation-review.schema.json')) {
        Write-ControllerFixtureText (Join-Path $fixture ('contracts/'+$schema)) ([IO.File]::ReadAllText((Join-Path $automationWorkspace ('contracts/'+$schema))))
    }
    $fixtureConfig=[IO.File]::ReadAllText((Join-Path $automationWorkspace 'contracts/automation.config.json')) | ConvertFrom-Json
    $fixtureConfig.maxSessionsPerTask=3; $fixtureConfig.maxProviderRetries=0; $fixtureConfig.invocationTimeoutSeconds=1; $fixtureConfig.maxRunHours=1
    Write-ControllerFixtureJson (Join-Path $fixture 'contracts/automation.config.json') $fixtureConfig
    Write-ControllerFixtureJson (Join-Path $fixture 'docs/sources/source-manifest.json') ([ordered]@{sources=@()})
    Write-ControllerFixtureText (Join-Path $fixture 'AGENTS.md') 'Synthetic controller fixture. No application or provider execution is permitted.'
    Write-ControllerFixtureText (Join-Path $fixture 'docs/execution/next-step.md') 'Synthetic initial work order.'
    Write-ControllerFixtureText (Join-Path $fixture 'docs/prompts/SUPERVISOR.md') 'Synthetic supervisor contract.'
    $tasks=@(); $rows=@()
    $md=@('# Synthetic controller ledger','','Application baseline on test date: no synthetic tasks accepted.','','| Task | Goal | Dependencies | Status | Attempts | Review | Evidence |','| --- | --- | --- | --- | --- | --- | --- |')
    for ($index=0;$index -lt $TaskIds.Count;$index++) {
        $id=$TaskIds[$index]
        $dependencies=@()
        if ($index -gt 0) {$dependencies=@($TaskIds[$index-1])}
        $tasks += [pscustomobject]@{id=$id;title='Synthetic '+$id;dependencies=@($dependencies);specPath='docs/features/'+$id+'.md';risk='NORMAL';requiredEntryPoints=@()}
        $rows += [pscustomobject]@{id=$id;status='TODO';reviewStatus='PENDING';attempts=0;revision=$null;evidence=@();notes='Synthetic fixture only.'}
        $md += '| '+$id+' | Synthetic '+$id+' | '+$(if ($dependencies.Count) {$dependencies -join ', '} else {'none'})+' | TODO | 0 | PENDING | none |'
        $spec=@"
# $id synthetic task

Planned allowed paths: ``src/``; ``scripts/``. Synthetic fixture only.

## Acceptance and expected checks

1. Synthetic task persists its own result.
2. Independent check verifies synthetic result.

## Evidence and review

No application acceptance is represented by this fixture.
"@
        Write-ControllerFixtureText (Join-Path $fixture ('docs/features/'+$id+'.md')) $spec
    }
    Write-ControllerFixtureJson (Join-Path $fixture 'contracts/tasks.json') ([ordered]@{schemaVersion='1.0';tasks=$tasks})
    Write-ControllerFixtureJson (Join-Path $fixture 'docs/execution/task-ledger.json') ([ordered]@{schemaVersion='1.0';updatedAt='test';tasks=$rows})
    Write-ControllerFixtureText (Join-Path $fixture 'docs/execution/task-ledger.md') ($md -join [Environment]::NewLine)
    return $fixture
}

$bootstrap=New-ControllerFixture 'bootstrap'
# Loading without Execute only exposes functions and previews an isolated fixture.
. (Join-Path $testScriptDirectory 'start-development.ps1') -Root $bootstrap | Out-Null

function Get-CodexCommand {param([string]$Command='codex') return [pscustomobject]@{path='mock-codex';version='MOCK_ONLY'}}
function Initialize-AutomationEnvironment {
    param([string]$Root,$Config,[string]$RunDirectory)
    [void][IO.Directory]::CreateDirectory($RunDirectory)
    return [pscustomobject]@{javaReady=$true;javaHome=$null;localAvailable=($script:mockMode -eq 'local-failover');localModel='fixture-local';issues=@();reportPath=$null}
}
function Invoke-AutomationLocalAdmission {param([string]$Root,$Config,[string]$Model,[string]$RunDirectory,[string]$CodexCommand) return [pscustomobject]@{admitted=$true;model=$Model;issues=@();evidencePaths=@()}}
function Invoke-AutomationAgent {
    param([string]$Root,[string]$Role,[string]$Model,[string]$Provider,[string]$Prompt,[string]$SchemaPath,[string]$RunDirectory,[int]$MaxRunSeconds,[string]$WindowsSandbox,[string]$CodexCommand,[switch]$ReadOnly,[string[]]$AllowedPaths)
    [void][IO.Directory]::CreateDirectory($RunDirectory)
    $idMatch=[regex]::Match($RunDirectory,'(?:^|[\\/])(T[0-9]{2})(?:[\\/]|$)')
    if (-not $idMatch.Success) {throw 'Mock agent task path is missing.'}
    $id=$idMatch.Groups[1].Value
    $task=@((Read-WorkflowJson (Join-Path $Root 'contracts/tasks.json')).tasks | Where-Object {$_.id -eq $id})[0]
    $criteria=Get-AutomationTaskCriteria $Root $task
    $script:mockEvents.Add([pscustomobject]@{role=$Role;taskId=$id;provider=$Provider;runDirectory=$RunDirectory})
    $result=$null; $valid=$true; $issues=@()
    if ($Role -eq 'Plan') {
        $mapping=@($criteria | ForEach-Object {[pscustomobject]@{criterion=$_;evidenceExpected=@('docs/verification/'+$id+'/check.log')}})
        $result=[pscustomobject]@{taskId=$id;goal='Complete synthetic task';allowedPaths=@('src/',('scripts/verify/verify-'+$id+'.ps1'),('docs/verification/'+$id+'/'));steps=@('Persist synthetic source and evidence');verificationScripts=@('scripts/verify/verify-'+$id+'.ps1');acceptanceMapping=$mapping;externalGates=@()}
        if ($script:mockMode -eq 'weakened-plan') {$result.acceptanceMapping[0].criterion='Weakened synthetic acceptance.'}
    } elseif ($Role -eq 'Implement') {
        $script:mockImplementations++
        if ($script:mockMode -eq 'local-failover' -and $Provider -eq 'lmstudio') {$valid=$false;$issues=@('Synthetic local provider timeout.')} else {
            Write-ControllerFixtureText (Join-Path $Root ('src/'+$id+'.txt')) ('implemented '+$id)
            Write-ControllerFixtureText (Join-Path $Root ('docs/verification/'+$id+'/check.log')) ('synthetic implementation check '+$id)
            Write-ControllerFixtureText (Join-Path $Root ('scripts/verify/verify-'+$id+'.ps1')) "throw 'Synthetic entrypoint: never executed by controller unit tests.'"
            $result=[pscustomobject]@{taskId=$id;status='NEEDS_REVIEW';revision='CAPTURED_BY_WRAPPER';summary='Synthetic implementation';changedFiles=@('src/'+$id+'.txt');checks=@([pscustomobject]@{command='MOCK_ONLY';exitCode=0;evidencePaths=@('docs/verification/'+$id+'/check.log')});risks=@();blockedReason=$null}
            if ($script:mockMode -eq 'implementer-pass') {$result.status='PASS'}
            if ($script:mockMode -eq 'protected-mutation') {Write-ControllerFixtureText (Join-Path $Root 'AGENTS.md') 'Changed protected fixture contract';$valid=$false;$issues=@('Protected controller/specification/progress file changed: AGENTS.md')}
            if ($script:mockMode -eq 'owner-forgery') {Write-ControllerFixtureJson (Join-Path $Root 'docs/execution/owner-acceptance.json') ([ordered]@{taskId='T42';decision='ACCEPTED';acceptedAtUtc=[DateTime]::UtcNow.ToString('o');owner='model'});$valid=$false;$issues=@('Protected controller/specification/progress file changed: docs/execution/owner-acceptance.json')}
            if ($script:mockMode -eq 'manual-forgery') {Write-ControllerFixtureJson (Join-Path $Root 'docs/execution/manual-accessibility-acceptance.json') ([ordered]@{taskId='T30';decision='VERIFIED';keyboardPassed=$true;screenReaderPassed=$true;tester='model'});$valid=$false;$issues=@('Protected controller/specification/progress file changed: docs/execution/manual-accessibility-acceptance.json')}
        }
    } elseif ($Role -in @('Review','Diagnose')) {
        $packet=Read-WorkflowJson (Join-Path (Split-Path -Parent $RunDirectory) 'review-packet.json')
        $decision=if ($script:mockMode -eq 'retry-limit' -or $Role -eq 'Diagnose') {'REQUEST_CHANGES'} else {'APPROVE'}
        $findings=if ($decision -eq 'REQUEST_CHANGES') {@([pscustomobject]@{severity='HIGH';message='Synthetic missing behavior';requiredAction='Repair the same synthetic root cause.'})} else {@()}
        $result=[pscustomobject]@{taskId=$id;reviewedRevision=$packet.sourceRevision;decision=$decision;taskComplete=($decision -eq 'APPROVE');summary='Synthetic separate review';findings=@($findings);criteria=@($packet.plan.acceptanceMapping | ForEach-Object {[pscustomobject]@{criterion=$_.criterion;passed=($decision -eq 'APPROVE');evidencePaths=@($_.evidenceExpected[0])}});limitations=@('MOCK_ONLY')}
        if ($script:mockMode -eq 'wrong-evidence-mapping') {$result.criteria[0].evidencePaths=@($packet.verification.evidencePaths[0])}
        if ($script:mockMode -eq 'stale-review') {$result.reviewedRevision='snapshot:wrong'}
        if ($script:mockMode -eq 'evidence-tamper') {Write-ControllerFixtureText (Join-Path $Root $packet.verification.evidencePaths[0]) 'Tampered ignored run evidence after verification.'}
        if ($script:mockMode -eq 'source-tamper') {Write-ControllerFixtureText (Join-Path $Root 'src/late.txt') 'Changed source during review.'}
    } else {throw 'Unexpected mock agent role.'}
    $resultPath=Join-Path $RunDirectory 'result.json'
    Write-ControllerFixtureJson $resultPath $result
    $summaryPath=Join-Path $RunDirectory 'run-summary.json'
    Write-ControllerFixtureJson $summaryPath ([ordered]@{role=$Role;valid=$valid;issues=$issues;mock=$true})
    $revision=(Get-SourceSnapshot $Root).revision
    return [pscustomobject]@{valid=$valid;result=$result;runSummaryPath=$summaryPath;sourceRevisionBefore=$revision;sourceRevisionAfter=$revision;issues=$issues;evidencePaths=@($summaryPath,$resultPath);changedSourcePaths=@()}
}
function Invoke-AutomationVerification {
    param([string]$Root,$Task,$Plan,[string]$RunDirectory,$Config)
    [void][IO.Directory]::CreateDirectory($RunDirectory)
    $script:mockEvents.Add([pscustomobject]@{role='Verify';taskId=$Task.id;provider=$null;runDirectory=$RunDirectory})
    $path=Join-Path $RunDirectory 'independent.log'
    Write-ControllerFixtureText $path ('Independent synthetic verification '+$Task.id)
    $passed=($script:mockMode -ne 'verification-failure')
    $relative=Get-AutomationRelativePath $Root $path
    $mappedEvidence='docs/verification/'+$Task.id+'/check.log'
    $check=[pscustomobject]@{name='Independent synthetic result check';passed=$passed;details=[pscustomobject]@{command='MOCK_ONLY';exitCode=$(if ($passed) {0} else {7});timedOut=$false};evidencePaths=@($relative,$mappedEvidence)}
    $reportPath=Join-Path $RunDirectory 'verification-report.json'
    $failures=@(); if (-not $passed) {$failures=@('Synthetic verifier exit 7')}
    Write-ControllerFixtureJson $reportPath ([ordered]@{passed=$passed;taskId=$Task.id;checks=@($check);failureReasons=$failures;evidence=@([ordered]@{path=$relative;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()},[ordered]@{path=$mappedEvidence;sha256=(Get-FileHash -LiteralPath (Join-Path $Root $mappedEvidence) -Algorithm SHA256).Hash.ToLowerInvariant()});taskApproval='REQUIRES_INDEPENDENT_GPT_REVIEW';providers='MOCK_ONLY'})
    return [pscustomobject]@{passed=$passed;checks=@($check);evidencePaths=@($relative,(Get-AutomationRelativePath $Root $reportPath),('docs/verification/'+$Task.id+'/check.log'));reportPath=(Get-AutomationRelativePath $Root $reportPath);failureReasons=$failures}
}
function Assert-ControllerTest {param([bool]$Condition,[string]$Message) if (-not $Condition) {throw $Message}}
function Reset-ControllerMock {param([string]$Mode) $script:mockMode=$Mode;$script:mockEvents.Clear();$script:mockImplementations=0}
function Invoke-ControllerFixture {param([string]$Fixture,[int]$MaxTasks=42,[string]$TaskId) $config=Read-WorkflowJson (Join-Path $Fixture 'contracts/automation.config.json'); return Invoke-AutomationCampaign -Root $Fixture -Config $config -MaxTasks $MaxTasks -TaskId $TaskId -CodexCommand mock}
function Get-ControllerLedgerRows {param([string]$Fixture) return @((Read-WorkflowJson (Join-Path $Fixture 'docs/execution/task-ledger.json')).tasks)}
function Test-ControllerCase {
    param([string]$Name,[scriptblock]$Body)
    try {& $Body; $script:caseResults.Add([pscustomobject]@{name=$Name;passed=$true;error=$null})}
    catch {$script:caseResults.Add([pscustomobject]@{name=$Name;passed=$false;error=$_.Exception.Message;stack=$_.ScriptStackTrace})}
}

Test-ControllerCase 'Two dependent tasks use GPT failover, independent verifier and separate reviewer in order' {
    Reset-ControllerMock success; $fixture=New-ControllerFixture sequence
    $state=Invoke-ControllerFixture $fixture
    Assert-ControllerTest ($state.status -eq 'COMPLETE') ('Expected synthetic completion; got '+$state.message)
    $rows=Get-ControllerLedgerRows $fixture
    Assert-ControllerTest (@($rows | Where-Object {$_.status -ne 'PASS' -or $_.reviewStatus -ne 'APPROVED' -or $_.attempts -ne 1}).Count -eq 0) 'Synthetic ledgers did not accept both tasks.'
    $eventOrder=(@($script:mockEvents | ForEach-Object {$_.taskId+':'+$_.role}) -join ',')
    Assert-ControllerTest ($eventOrder -eq 'T01:Plan,T01:Implement,T01:Verify,T01:Review,T02:Plan,T02:Implement,T02:Verify,T02:Review') ('Wrong phase/dependency order: '+$eventOrder)
    Assert-ControllerTest (@($script:mockEvents | Where-Object {$_.role -eq 'Implement' -and $_.provider}).Count -eq 0) 'Unavailable local provider was selected.'
    $md=Get-Content -LiteralPath (Join-Path $fixture 'docs/execution/task-ledger.md') -Raw
    Assert-ControllerTest ($md -match '\| T01 \|.+\| PASS \| 1 \| APPROVED \|' -and $md -match '\| T02 \|.+\| PASS \| 1 \| APPROVED \|') 'Markdown ledger differs from accepted machine ledger.'
}
Test-ControllerCase 'Verified accepted tasks are skipped on resume without new implementation attempts' {
    Reset-ControllerMock success; $fixture=New-ControllerFixture resume
    $first=Invoke-ControllerFixture $fixture; Assert-ControllerTest ($first.status -eq 'COMPLETE') ('First run failed: '+$first.message)
    $script:mockEvents.Clear(); $script:mockImplementations=0
    $second=Invoke-ControllerFixture $fixture
    Assert-ControllerTest ($second.status -eq 'COMPLETE' -and $script:mockImplementations -eq 0 -and $script:mockEvents.Count -eq 0) ('Accepted resume reimplemented or failed: '+$second.message)
}
Test-ControllerCase 'Task budget checkpoints after acceptance and resumes the next dependency only' {
    Reset-ControllerMock success; $fixture=New-ControllerFixture budget-resume
    $first=Invoke-ControllerFixture $fixture -MaxTasks 1
    $rows=Get-ControllerLedgerRows $fixture
    Assert-ControllerTest ($first.status -eq 'CHECKPOINT' -and $first.phase -eq 'BUDGET_CHECKPOINT' -and $rows[0].status -eq 'PASS' -and $rows[1].status -eq 'TODO') ('Task budget did not checkpoint correctly: '+$first.message)
    $script:mockEvents.Clear(); $script:mockImplementations=0
    $second=Invoke-ControllerFixture $fixture
    Assert-ControllerTest ($second.status -eq 'COMPLETE' -and $script:mockImplementations -eq 1 -and @($script:mockEvents | Where-Object {$_.taskId -eq 'T01'}).Count -eq 0) ('Checkpoint resume redid accepted work: '+$second.message)
}
Test-ControllerCase 'Local transport failure switches the next session to authorized GPT implementation' {
    Reset-ControllerMock local-failover; $fixture=New-ControllerFixture local-failover @('T01')
    $state=Invoke-ControllerFixture $fixture
    $implementers=@($script:mockEvents | Where-Object {$_.role -eq 'Implement'})
    Assert-ControllerTest ($state.status -eq 'COMPLETE' -and $implementers.Count -eq 2 -and $implementers[0].provider -eq 'lmstudio' -and -not $implementers[1].provider) ('GPT failover did not accept after local transport failure: '+$state.message)
    Assert-ControllerTest ((Get-ControllerLedgerRows $fixture)[0].attempts -eq 2) 'Both implementation attempts were not recorded.'
}
Test-ControllerCase 'Failed independent verification cannot receive diagnostic approval or unlock dependency' {
    Reset-ControllerMock verification-failure; $fixture=New-ControllerFixture verification-failure
    $state=Invoke-ControllerFixture $fixture; $rows=Get-ControllerLedgerRows $fixture
    Assert-ControllerTest ($state.status -eq 'BLOCKED' -and $state.message -match 'Diagnostic/failed') ('Diagnostic approval was not rejected: '+$state.message)
    Assert-ControllerTest ($rows[0].status -ne 'PASS' -and $rows[1].status -eq 'TODO' -and @($script:mockEvents | Where-Object {$_.taskId -eq 'T02'}).Count -eq 0) 'Failed verification unlocked a dependency.'
}
foreach ($mode in @('stale-review','evidence-tamper','source-tamper')) {
    $caseMode=$mode
    Test-ControllerCase ('Reject '+$caseMode+' before task acceptance') {
        Reset-ControllerMock $caseMode; $fixture=New-ControllerFixture $caseMode @('T01')
        $state=Invoke-ControllerFixture $fixture
        Assert-ControllerTest ($state.status -eq 'BLOCKED' -and (Get-ControllerLedgerRows $fixture)[0].status -ne 'PASS') ('Integrity violation accepted: '+$state.message)
        $expected=if ($caseMode -eq 'stale-review') {'exact-revision'} elseif ($caseMode -eq 'evidence-tamper') {'Evidence changed'} else {'Source changed'}
        Assert-ControllerTest ($state.message -match $expected) ('Unexpected rejection reason: '+$state.message)
    }
}
Test-ControllerCase 'Protected implementation mutation is fatal before verification, review or failover' {
    Reset-ControllerMock protected-mutation; $fixture=New-ControllerFixture protected-mutation @('T01')
    $state=Invoke-ControllerFixture $fixture
    Assert-ControllerTest ($state.status -eq 'BLOCKED' -and $state.message -match 'Protected' -and $script:mockImplementations -eq 1) ('Protected mutation did not halt: '+$state.message)
    Assert-ControllerTest (@($script:mockEvents | Where-Object {$_.role -in @('Verify','Review','Diagnose')}).Count -eq 0) 'Controller continued after protected mutation.'
}
Test-ControllerCase 'Plan cannot weaken exact canonical acceptance criteria' {
    Reset-ControllerMock weakened-plan; $fixture=New-ControllerFixture weakened-plan @('T01')
    $state=Invoke-ControllerFixture $fixture
    Assert-ControllerTest ($state.status -eq 'BLOCKED' -and $state.message -match 'weakened/changed' -and $script:mockImplementations -eq 0) ('Weakened plan was allowed: '+$state.message)
}
Test-ControllerCase 'Implementer self-approval is rejected before verification' {
    Reset-ControllerMock implementer-pass; $fixture=New-ControllerFixture implementer-pass @('T01')
    $state=Invoke-ControllerFixture $fixture
    Assert-ControllerTest ($state.status -eq 'BLOCKED' -and (Get-ControllerLedgerRows $fixture)[0].status -ne 'PASS' -and @($script:mockEvents | Where-Object {$_.role -eq 'Verify'}).Count -eq 0) 'Implementer PASS was accepted.'
}
Test-ControllerCase 'Bounded repairs trigger diagnosis and stop at configured session ceiling' {
    Reset-ControllerMock retry-limit; $fixture=New-ControllerFixture retry-limit @('T01')
    $state=Invoke-ControllerFixture $fixture
    Assert-ControllerTest ($state.status -eq 'BLOCKED' -and $state.message -match 'REPAIR_LIMIT' -and $script:mockImplementations -eq 3) ('Session ceiling was not enforced: '+$state.message)
    Assert-ControllerTest (@($script:mockEvents | Where-Object {$_.role -eq 'Diagnose'}).Count -eq 1) 'Two repeated root causes did not receive focused diagnosis.'
}
Test-ControllerCase 'Historical evidence tampering is rejected before accepted-task skip' {
    Reset-ControllerMock success; $fixture=New-ControllerFixture historical-tamper @('T01')
    $state=Invoke-ControllerFixture $fixture; Assert-ControllerTest ($state.status -eq 'COMPLETE') ('Initial acceptance failed: '+$state.message)
    $acceptance=Read-WorkflowJson (Join-Path $fixture $state.acceptedTasks[0].acceptancePath)
    Write-ControllerFixtureText (Join-Path $fixture $acceptance.evidence[0].path) 'Changed historical evidence.'
    $script:mockEvents.Clear(); $state=Invoke-ControllerFixture $fixture
    Assert-ControllerTest ($state.status -eq 'BLOCKED' -and $state.message -match 'Evidence changed' -and $script:mockEvents.Count -eq 0) ('Historical evidence accepted: '+$state.message)
}
Test-ControllerCase 'Exclusive workspace lock refuses a concurrent controller before provider calls' {
    Reset-ControllerMock success; $fixture=New-ControllerFixture lock @('T01')
    $control=Join-Path $fixture 'docs/execution/runs/automatic'; [void][IO.Directory]::CreateDirectory($control)
    $ownedLock=[IO.File]::Open((Join-Path $control 'controller.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $rejected=$false
    try {try {$unused=Invoke-ControllerFixture $fixture} catch {$rejected=$_.Exception.Message -match 'Another automatic controller'}} finally {$ownedLock.Dispose()}
    Assert-ControllerTest ($rejected -and $script:mockEvents.Count -eq 0) 'Concurrent controller was allowed.'
}
Test-ControllerCase 'Interrupted two-ledger transaction recovers both matching views' {
    Reset-ControllerMock success; $fixture=New-ControllerFixture journal @('T01')
    $control=Join-Path $fixture 'docs/execution/runs/automatic'; [void][IO.Directory]::CreateDirectory($control)
    Set-AutomationTaskLedger -Root $fixture -ControlDirectory $control -TaskId T01 -Status IN_PROGRESS -IncrementAttempt -Notes 'Synthetic interrupted transaction.'
    $journalPath=Join-Path $control 'ledger-transaction.json'; $journal=Read-WorkflowJson $journalPath; $journal.committed=$false
    Write-ControllerFixtureJson $journalPath $journal
    Write-ControllerFixtureText (Join-Path $fixture $journal.files[1].path) $journal.files[1].before
    Recover-AutomationLedger $fixture $control
    foreach ($record in $journal.files) {Assert-ControllerTest ([IO.File]::ReadAllText((Join-Path $fixture $record.path)) -ceq $record.after) 'Recovery did not commit both views.'}
    Assert-ControllerTest ((Read-WorkflowJson $journalPath).committed -eq $true) 'Recovered transaction was not committed.'
}
Test-ControllerCase 'Transaction recovery preserves an unrelated conflicting ledger edit' {
    Reset-ControllerMock success; $fixture=New-ControllerFixture journal-conflict @('T01')
    $control=Join-Path $fixture 'docs/execution/runs/automatic'; [void][IO.Directory]::CreateDirectory($control)
    Set-AutomationTaskLedger -Root $fixture -ControlDirectory $control -TaskId T01 -Status IN_PROGRESS -IncrementAttempt -Notes 'Synthetic interrupted transaction.'
    $journalPath=Join-Path $control 'ledger-transaction.json'; $journal=Read-WorkflowJson $journalPath; $journal.committed=$false; Write-ControllerFixtureJson $journalPath $journal
    $conflict='Unrelated owner edit'; Write-ControllerFixtureText (Join-Path $fixture $journal.files[1].path) $conflict
    $rejected=$false; try {Recover-AutomationLedger $fixture $control} catch {$rejected=$_.Exception.Message -match 'Unrelated ledger edit'}
    Assert-ControllerTest ($rejected -and [IO.File]::ReadAllText((Join-Path $fixture $journal.files[1].path)) -ceq $conflict) 'Recovery overwrote unrelated work.'
}
Test-ControllerCase 'Committed-ledger tampering blocks recovery, supervisor updates and resume without overwriting raw files' {
    Reset-ControllerMock success; $fixture=New-ControllerFixture committed-ledger-tamper @('T01')
    $control=Join-Path $fixture 'docs/execution/runs/automatic'; [void][IO.Directory]::CreateDirectory($control)
    Set-AutomationTaskLedger -Root $fixture -ControlDirectory $control -TaskId T01 -Status IN_PROGRESS -IncrementAttempt -Notes 'Synthetic committed baseline.'
    $jsonPath=Join-Path $fixture 'docs/execution/task-ledger.json'; $mdPath=Join-Path $fixture 'docs/execution/task-ledger.md'
    $tamperedJson=[IO.File]::ReadAllText($jsonPath)+[Environment]::NewLine
    Write-ControllerFixtureText $jsonPath $tamperedJson
    $rawMarkdown=[IO.File]::ReadAllText($mdPath)
    $rejected=$false; try {Recover-AutomationLedger $fixture $control} catch {$rejected=$_.Exception.Message -match 'Ledger integrity changed'}
    Assert-ControllerTest $rejected 'Committed journal ignored a raw JSON ledger change.'
    $updateRejected=$false; try {Set-AutomationTaskLedger -Root $fixture -ControlDirectory $control -TaskId T01 -Status BLOCKED -Notes 'Must not overwrite the tampered ledger.'} catch {$updateRejected=$_.Exception.Message -match 'Ledger integrity changed'}
    Assert-ControllerTest $updateRejected 'Supervisor update overwrote a tampered committed ledger.'
    $resumeRejected=$false; try {$unused=Invoke-ControllerFixture $fixture} catch {$resumeRejected=$_.Exception.Message -match 'Ledger integrity changed'}
    Assert-ControllerTest ($resumeRejected -and $script:mockEvents.Count -eq 0) 'Resume proceeded after committed ledger tampering.'
    Assert-ControllerTest ([IO.File]::ReadAllText($jsonPath) -ceq $tamperedJson -and [IO.File]::ReadAllText($mdPath) -ceq $rawMarkdown) 'Raw ledger files were replaced while reporting integrity failure.'
}
Test-ControllerCase 'An acceptance archive junction is rejected before any copy reaches its target' {
    Reset-ControllerMock success; $fixture=New-ControllerFixture archive-junction @('T01')
    $target=Join-Path $testOutput ('archive-junction-target-'+[Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($target)
    $sentinel=Join-Path $target 'sentinel.txt'; Write-ControllerFixtureText $sentinel 'Preserved outside-fixture archive target.'
    $archive=Join-Path $fixture 'docs/execution/runs/accepted-evidence'; [void][IO.Directory]::CreateDirectory((Split-Path -Parent $archive))
    New-Item -ItemType Junction -Path $archive -Target $target -ErrorAction Stop | Out-Null
    $evidence='docs/verification/T01/source-proof.log'; Write-ControllerFixtureText (Join-Path $fixture $evidence) 'Synthetic source evidence.'
    $records=@([pscustomobject]@{path=$evidence;sha256=(Get-FileHash -LiteralPath (Join-Path $fixture $evidence) -Algorithm SHA256).Hash.ToLowerInvariant()})
    $rejected=$false; try {$unused=Copy-AutomationAcceptanceEvidence $fixture $records $archive} catch {$rejected=$_.Exception.Message -match 'Reparse'}
    Assert-ControllerTest ($rejected -and @(Get-ChildItem -LiteralPath $target -Force).Count -eq 1 -and [IO.File]::ReadAllText($sentinel) -ceq 'Preserved outside-fixture archive target.') 'Archive copy followed a junction or altered its target.'
}
Test-ControllerCase 'T42 cannot pass without separately recorded actual owner acceptance' {
    Reset-ControllerMock success; $fixture=New-ControllerFixture owner-required @('T42')
    $state=Invoke-ControllerFixture $fixture
    Assert-ControllerTest ($state.status -eq 'BLOCKED' -and (Get-ControllerLedgerRows $fixture)[0].status -ne 'PASS' -and $state.message -match 'owner-acceptance|OWNER_ACCEPTANCE') ('Missing owner acceptance passed: '+$state.message)
}
Test-ControllerCase 'A model-generated owner acceptance is a protected mutation and cannot unlock T42' {
    Reset-ControllerMock owner-forgery; $fixture=New-ControllerFixture owner-forgery @('T42')
    $state=Invoke-ControllerFixture $fixture
    Assert-ControllerTest ($state.status -eq 'BLOCKED' -and $state.message -match 'Protected' -and (Get-ControllerLedgerRows $fixture)[0].status -ne 'PASS' -and @($script:mockEvents | Where-Object {$_.role -eq 'Review'}).Count -eq 0) 'Forged owner acceptance was allowed.'
}
Test-ControllerCase 'Reviewer cannot substitute unrelated evidence for an exact criterion mapping' {
    Reset-ControllerMock wrong-evidence-mapping; $fixture=New-ControllerFixture wrong-evidence-mapping @('T01')
    $state=Invoke-ControllerFixture $fixture
    Assert-ControllerTest ($state.status -eq 'BLOCKED' -and $state.message -match 'declared verification mapping' -and (Get-ControllerLedgerRows $fixture)[0].status -ne 'PASS') ('Unmapped evidence was accepted: '+$state.message)
}
Test-ControllerCase 'T30 cannot pass from automation without actual keyboard and screen-reader acceptance' {
    Reset-ControllerMock success; $fixture=New-ControllerFixture manual-required @('T30')
    $state=Invoke-ControllerFixture $fixture
    Assert-ControllerTest ($state.status -eq 'BLOCKED' -and (Get-ControllerLedgerRows $fixture)[0].status -ne 'PASS' -and $state.message -match 'manual-accessibility|MANUAL_ACCESSIBILITY') ('Missing manual evidence passed: '+$state.message)
}
Test-ControllerCase 'A model-generated manual acceptance is a protected mutation and cannot unlock T30' {
    Reset-ControllerMock manual-forgery; $fixture=New-ControllerFixture manual-forgery @('T30')
    $state=Invoke-ControllerFixture $fixture
    Assert-ControllerTest ($state.status -eq 'BLOCKED' -and $state.message -match 'Protected' -and (Get-ControllerLedgerRows $fixture)[0].status -ne 'PASS' -and @($script:mockEvents | Where-Object {$_.role -eq 'Review'}).Count -eq 0) 'Forged manual acceptance was allowed.'
}
Test-ControllerCase 'Manual acceptance is bound to product source and requires actual boolean results' {
    Reset-ControllerMock success; $fixture=New-ControllerFixture manual-record @('T30')
    $task=(Read-WorkflowJson (Join-Path $fixture 'contracts/tasks.json')).tasks[0]
    $config=Read-WorkflowJson (Join-Path $fixture 'contracts/automation.config.json')
    $evidence='docs/verification/T30/manual.log'; Write-ControllerFixtureText (Join-Path $fixture $evidence) 'Synthetic human checklist proof.'
    $record=[pscustomobject]@{taskId='T30';decision='VERIFIED';tester='Synthetic tester';environment='Synthetic test only';verifiedAtUtc=[DateTime]::UtcNow.ToString('o');keyboardPassed=$true;screenReaderPassed=$true;reviewedProductRevision='product:stale';evidencePaths=@($evidence)}
    $recordPath=Join-Path $fixture 'docs/execution/manual-accessibility-acceptance.json'; Write-ControllerFixtureJson $recordPath $record
    $rejected=$false; try {Assert-AutomationHumanGate $fixture $task $config} catch {$rejected=$_.Exception.Message -match 'MANUAL_ACCESSIBILITY_REQUIRED'}
    Assert-ControllerTest $rejected 'Stale manual acceptance was accepted.'
    $record.reviewedProductRevision=Get-AutomationProductRevision $fixture; Write-ControllerFixtureJson $recordPath $record
    Assert-AutomationHumanGate $fixture $task $config
    $record.keyboardPassed='false'; Write-ControllerFixtureJson $recordPath $record
    $rejected=$false; try {Assert-AutomationHumanGate $fixture $task $config} catch {$rejected=$_.Exception.Message -match 'MANUAL_ACCESSIBILITY_REQUIRED'}
    Assert-ControllerTest $rejected 'Non-boolean manual result was accepted.'
}

$productionLedgerAfter=@{}
foreach ($ledgerView in @('docs/execution/task-ledger.json','docs/execution/task-ledger.md')) {
    $productionLedgerAfter[$ledgerView]=(Get-FileHash -LiteralPath (Join-Path $automationWorkspace $ledgerView) -Algorithm SHA256).Hash
}
Test-ControllerCase 'Actual application ledger views remain byte-identical throughout isolated tests' {
    foreach ($ledgerView in $productionLedgerBefore.Keys) {Assert-ControllerTest ($productionLedgerBefore[$ledgerView] -ceq $productionLedgerAfter[$ledgerView]) ('Application ledger changed during test process: '+$ledgerView)}
}
$results=$script:caseResults.ToArray()
$failures=@($results | Where-Object {-not $_.passed})
$report=[ordered]@{schemaVersion=1;executedAtUtc=[DateTime]::UtcNow.ToString('o');powerShell=$testHostVersion;passed=($failures.Count -eq 0);checkCount=$results.Count;checks=$results;fixtureDirectory=$testOutput;providers='MOCK_ONLY';applicationAcceptance=$false;actualControllerLoopTested=$true;productionLedgerBefore=$productionLedgerBefore;productionLedgerAfter=$productionLedgerAfter;productionLedgerChanged=(@($productionLedgerBefore.Keys | Where-Object {$productionLedgerBefore[$_] -cne $productionLedgerAfter[$_]}).Count -gt 0);note='Only isolated synthetic fixture ledgers/source were modified. No model, service, installer or application verification was executed.'}
$reportPath=Join-Path $testOutput 'controller-self-test.json'; Write-ControllerFixtureJson $reportPath $report
[pscustomobject]@{passed=$report.passed;checkCount=$results.Count;failedChecks=@($failures);reportPath=$reportPath;providers='MOCK_ONLY';applicationAcceptance=$false} | ConvertTo-Json -Depth 10
if ($failures.Count) {throw 'Automatic controller self-test failed; inspect preserved report.'}
