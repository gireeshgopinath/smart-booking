[CmdletBinding()]
param([string]$Root)
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PSScriptRoot 'workflow-common.ps1')
$fixture = New-WorkflowDirectory $Root '' 'workflow-self-test'
[void][IO.Directory]::CreateDirectory((Join-Path $fixture 'contracts'))
[void][IO.Directory]::CreateDirectory((Join-Path $fixture 'docs/features'))
[void][IO.Directory]::CreateDirectory((Join-Path $fixture 'scripts'))
Copy-Item -LiteralPath (Join-Path $Root 'scripts') -Destination $fixture -Recurse -Force
foreach ($schema in @('local-result.schema.json','review-result.schema.json')) {
    Copy-Item -LiteralPath (Join-Path $Root ('contracts/' + $schema)) -Destination (Join-Path $fixture 'contracts')
}
$tasks = @([ordered]@{id='T01';title='Mock workflow feature';dependencies=@();specPath='docs/features/T01.md'}, [ordered]@{id='T02';title='Dependency-gated mock';dependencies=@('T01');specPath='docs/features/T02.md'})
Write-NewJson (Join-Path $fixture 'contracts/tasks.json') ([ordered]@{schemaVersion='1.0';tasks=$tasks})
Write-NewJson (Join-Path $fixture 'docs/execution/task-ledger.json') ([ordered]@{schemaVersion='1.0';tasks=@([ordered]@{id='T01';status='TODO';attempts=0;reviewStatus='PENDING';revision=$null;evidence=@();notes='MOCK ONLY'},[ordered]@{id='T02';status='TODO';attempts=0;reviewStatus='PENDING';revision=$null;evidence=@();notes='MOCK ONLY'})})
Write-NewUtf8 (Join-Path $fixture 'docs/features/T01.md') '# T01: workflow mock; this is not an application acceptance test.'
Write-NewUtf8 (Join-Path $fixture 'docs/features/T02.md') '# T02: reject until T01 has real evidence and independent approval.'
Write-NewUtf8 (Join-Path $fixture 'docs/execution/evidence/mock.txt') 'Workflow mock fixture only. No application test or live model was used.'
Write-NewUtf8 (Join-Path $fixture 'src/feature.txt') 'Synthetic source sanitizer fixture password=mock-source-secret'
$mock = @'
$invocationArgs = @($args)
if ($invocationArgs[0] -eq '--version') { 'codex-cli MOCK'; exit 0 }
if ($invocationArgs.Count -eq 2 -and $invocationArgs[1] -eq '--help') { '--output-schema --output-last-message --sandbox --ignore-user-config --oss --local-provider'; exit 0 }
$prompt = $input | Out-String
$model = $invocationArgs[[array]::IndexOf($invocationArgs,'--model') + 1]
if ($model -eq 'gpt-timeout') { Start-Sleep -Seconds 15; exit 0 }
if ($model -eq 'gpt-failure') { [Console]::Error.WriteLine('intentional mock CLI failure; Authorization: Bearer mock-secret-value'); exit 9 }
$resultPath = $invocationArgs[[array]::IndexOf($invocationArgs,'--output-last-message') + 1]
if ($prompt -notmatch '"sourceRevision"\s*:\s*"(snapshot:[a-f0-9]+)"') { [Console]::Error.WriteLine('missing packet revision'); exit 8 }
$result = [ordered]@{taskId='T01';reviewedRevision=$Matches[1];decision='REQUEST_CHANGES';summary='Mock supervision transport check only';findings=@();evidenceReviewed=@('docs/execution/evidence/mock.txt');limitations=@('MOCK CLI: does not establish application acceptance or model capability.')}
if ($model -eq 'gpt-approve') { $result.decision = 'APPROVE' }
if ($model -eq 'gpt-ledger-mutation') {
    $rootPath = $invocationArgs[[array]::IndexOf($invocationArgs,'--cd') + 1]
    [IO.File]::WriteAllText((Join-Path $rootPath 'docs/execution/task-ledger.md'),'MOCK forbidden ledger write')
}
$json = $result | ConvertTo-Json -Depth 10
[IO.File]::WriteAllText($resultPath,$json,(New-Object Text.UTF8Encoding($false)))
'Mock CLI received stdin and emitted schema-shaped review result.'
exit 0
'@
$mockPath = Join-Path $fixture 'scripts/mock-codex.ps1'
Write-NewUtf8 $mockPath $mock
$results = New-Object 'System.Collections.Generic.List[object]'
$preview = & (Join-Path $fixture 'scripts/prepare-task.ps1') -Root $fixture -TaskId T01 -DryRun | ConvertFrom-Json
if (-not $preview.dependencyReady -or $preview.writesFiles) { throw 'T01 read-only preparation failed.' }
$results.Add([pscustomobject]@{check='dependency-ready dry run';result='PASS'})
try { & (Join-Path $fixture 'scripts/prepare-task.ps1') -Root $fixture -TaskId T02 -DryRun | Out-Null; throw 'UNEXPECTED_READY' }
catch { if ($_.Exception.Message -notmatch 'Dependency T01 is not verified') { throw } }
$results.Add([pscustomobject]@{check='unmet dependency rejection';result='PASS'})
& (Join-Path $fixture 'scripts/verify-workflow.ps1') -Root $fixture -ExpectedTaskCount 2 | Out-Null
$results.Add([pscustomobject]@{check='graph/schema/scripts verification';result='PASS'})
$snapshot = Get-SourceSnapshot $fixture
$localDirectory = New-WorkflowDirectory $fixture 'docs/execution/runs/mock-local' 'unused'
$localResult = [ordered]@{taskId='T01';status='NEEDS_REVIEW';revision='CAPTURED_BY_WRAPPER';summary='Workflow fixture only api_key=mock-summary-secret';changedFiles=@('src/feature.txt');checks=@([ordered]@{command='mock evidence fixture';exitCode=0;evidencePaths=@('docs/execution/evidence/mock.txt')});risks=@('MOCK ONLY');blockedReason=$null}
Write-NewJson (Join-Path $localDirectory 'result.json') $localResult
Write-NewJson (Join-Path $localDirectory 'run-summary.json') ([ordered]@{taskId='T01';role='Local';wrapperValid=$true;cliExitCode=0;sourceRevisionAfter=$snapshot.revision;changedSourcePaths=@()})
$packetInfo = & (Join-Path $fixture 'scripts/build-review-packet.ps1') -Root $fixture -TaskId T01 -RunDirectory 'docs/execution/runs/mock-local' -OutputDirectory 'docs/execution/runs/mock-packet' | ConvertFrom-Json
$packetText = Get-Content -LiteralPath (Join-Path $fixture $packetInfo.packetPath) -Raw -Encoding UTF8
$parsedPacket = $packetText | ConvertFrom-Json
if ($packetText.Contains('mock-summary-secret') -or $packetText.Contains('mock-source-secret') -or $parsedPacket.evidence[0].path -ne 'docs/execution/evidence/mock.txt' -or $parsedPacket.sourceFiles[0].path -ne 'src/feature.txt') { throw 'Packet sanitizer failed or altered evidence/source paths.' }
$results.Add([pscustomobject]@{check='string-leaf sanitization and parseable JSON';result='PASS'})
$summary = & (Join-Path $fixture 'scripts/run-codex-task.ps1') -Root $fixture -TaskId T01 -Role Review -Model 'gpt-mock' -CodexCommand $mockPath -ReviewPacketPath $packetInfo.packetPath -OutputDirectory 'docs/execution/runs/mock-review' -Execute -MaxRunSeconds 20 | ConvertFrom-Json
if (-not $summary.wrapperValid -or $summary.cliExitCode -ne 0 -or $summary.ledgerChanged) { throw 'Mock review invocation failed.' }
$results.Add([pscustomobject]@{check='bounded mock CLI/stdin/result/review packet';result='PASS'})
try { & (Join-Path $fixture 'scripts/prepare-task.ps1') -Root $fixture -TaskId T01 -OutputDirectory 'docs/execution/runs/mock-packet' | Out-Null; throw 'UNEXPECTED_OVERWRITE' }
catch { if ($_.Exception.Message -notmatch 'Refusing to overwrite') { throw } }
$results.Add([pscustomobject]@{check='existing output overwrite rejection';result='PASS'})
$bad = $localResult | ConvertTo-Json -Depth 20 | ConvertFrom-Json
$bad.status = 'PASS'
try { Assert-ResultShape $bad Local T01; throw 'UNEXPECTED_PASS' } catch { if ($_.Exception.Message -notmatch 'schema enum|forbidden status') { throw } }
$results.Add([pscustomobject]@{check='implementer PASS rejection';result='PASS'})
try { & (Join-Path $fixture 'scripts/run-codex-task.ps1') -Root $fixture -TaskId T01 -Role Review -Model 'gpt-failure' -CodexCommand $mockPath -ReviewPacketPath $packetInfo.packetPath -OutputDirectory 'docs/execution/runs/mock-failure' -Execute -MaxRunSeconds 20 | Out-Null; throw 'UNEXPECTED_SUCCESS' }
catch { if ($_.Exception.Message -notmatch 'Run rejected') { throw } }
$failed = Read-WorkflowJson (Join-Path $fixture 'docs/execution/runs/mock-failure/run-summary.json')
if ($failed.cliExitCode -ne 9 -or $failed.wrapperValid) { throw 'Nonzero mock exit was not preserved/rejected.' }
$results.Add([pscustomobject]@{check='nonzero CLI exit capture and rejection';result='PASS'})
$diagnosticInfo = & (Join-Path $fixture 'scripts/build-review-packet.ps1') -Root $fixture -TaskId T01 -RunDirectory 'docs/execution/runs/mock-failure' -OutputDirectory 'docs/execution/runs/mock-diagnostic' -Diagnostic | ConvertFrom-Json
$diagnosticText = Get-Content -LiteralPath (Join-Path $fixture $diagnosticInfo.packetPath) -Raw -Encoding UTF8
$diagnostic = $diagnosticText | ConvertFrom-Json
if ($diagnostic.purpose -ne 'DIAGNOSTIC' -or $diagnostic.runSummary.cliExitCode -ne 9 -or $diagnostic.runSummary.wrapperValid -or $diagnosticText.Contains('mock-secret-value')) { throw 'Diagnostic packet lost failure state or did not redact logs.' }
$results.Add([pscustomobject]@{check='rejected/missing-result diagnostic preserves exit and redacts log';result='PASS'})
try { & (Join-Path $fixture 'scripts/run-codex-task.ps1') -Root $fixture -TaskId T01 -Role Review -Model 'gpt-approve' -CodexCommand $mockPath -ReviewPacketPath $diagnosticInfo.packetPath -OutputDirectory 'docs/execution/runs/mock-diagnostic-approval' -Execute -MaxRunSeconds 20 | Out-Null; throw 'UNEXPECTED_APPROVAL' }
catch { if ($_.Exception.Message -notmatch 'Run rejected') { throw } }
$invalidApproval = Read-WorkflowJson (Join-Path $fixture 'docs/execution/runs/mock-diagnostic-approval/run-summary.json')
if ($invalidApproval.wrapperValid -or @($invalidApproval.issues | Where-Object {$_ -match 'Diagnostic packets cannot receive APPROVE'}).Count -eq 0) { throw 'Diagnostic APPROVE was not rejected.' }
$results.Add([pscustomobject]@{check='diagnostic approval rejection';result='PASS'})
try { & (Join-Path $fixture 'scripts/run-codex-task.ps1') -Root $fixture -TaskId T01 -Role Review -Model 'gpt-timeout' -CodexCommand $mockPath -ReviewPacketPath $packetInfo.packetPath -OutputDirectory 'docs/execution/runs/mock-timeout' -Execute -MaxRunSeconds 2 | Out-Null; throw 'UNEXPECTED_SUCCESS' }
catch { if ($_.Exception.Message -notmatch 'Run rejected') { throw } }
$timeout = Read-WorkflowJson (Join-Path $fixture 'docs/execution/runs/mock-timeout/run-summary.json')
if (-not $timeout.process.timedOut -or $timeout.cliExitCode -ne 124 -or $timeout.wrapperValid) { throw 'Owned timeout was not captured/rejected.' }
$results.Add([pscustomobject]@{check='owned process deadline/termination';result='PASS'})
$timeoutInfo = & (Join-Path $fixture 'scripts/build-review-packet.ps1') -Root $fixture -TaskId T01 -RunDirectory 'docs/execution/runs/mock-timeout' -OutputDirectory 'docs/execution/runs/mock-timeout-diagnostic' -Diagnostic | ConvertFrom-Json
$timeoutDiagnostic = Read-WorkflowJson (Join-Path $fixture $timeoutInfo.packetPath)
if ($timeoutDiagnostic.purpose -ne 'DIAGNOSTIC' -or $timeoutDiagnostic.runSummary.cliExitCode -ne 124 -or -not $timeoutDiagnostic.runSummary.process.timedOut) { throw 'Timed-out diagnostic lost deadline state.' }
$results.Add([pscustomobject]@{check='timed-out diagnostic preserves timeout state';result='PASS'})
try { & (Join-Path $fixture 'scripts/run-codex-task.ps1') -Root $fixture -TaskId T01 -Role Review -Model 'gpt-ledger-mutation' -CodexCommand $mockPath -ReviewPacketPath $packetInfo.packetPath -OutputDirectory 'docs/execution/runs/mock-ledger-mutation' -Execute -MaxRunSeconds 20 | Out-Null; throw 'UNEXPECTED_LEDGER_WRITE' }
catch { if ($_.Exception.Message -notmatch 'Run rejected') { throw } }
$mutation = Read-WorkflowJson (Join-Path $fixture 'docs/execution/runs/mock-ledger-mutation/run-summary.json')
if (-not $mutation.ledgerChanged -or $mutation.wrapperValid -or @($mutation.issues | Where-Object { $_ -match 'modified a task ledger' }).Count -eq 0) { throw 'Markdown ledger mutation was not detected/rejected.' }
$results.Add([pscustomobject]@{check='Markdown ledger mutation rejection';result='PASS'})
$report = [ordered]@{valid=$true;powershell=$PSVersionTable.PSVersion.ToString();fixtureDirectory=$fixture;checks=$results.ToArray();liveModel='NOT_RUN';applicationTests='NOT_RUN';ledgerPromoted=$false}
Write-NewJson (Join-Path $fixture 'self-test-summary.json') $report
$report | ConvertTo-Json -Depth 10
