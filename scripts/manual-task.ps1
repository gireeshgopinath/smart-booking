# Windows PowerShell 5.1 entrypoint; the task engine runs in PowerShell 7.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^T[0-9]{2}$')][string]$TaskId,
    [Parameter(Mandatory)][ValidateSet('Plan','Prepare','Start','Verify','Finish')][string]$Action,
    [string]$Root,
    [string]$PlanPath,
    [ValidateSet('gpt','lmstudio')][string]$Provider='lmstudio',
    [string]$Model,
    [string]$CodexCommand='codex',
    [switch]$Execute,
    [switch]$ExclusiveWriterConfirmed
)
$ErrorActionPreference='Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) {
    $pwshCommand=Get-Command pwsh.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $pwshPath=if ($pwshCommand) {$pwshCommand.Source} else {$null}
    if (-not $pwshPath) {
        $candidates=@(
            (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe'),
            (Join-Path $env:ProgramFiles 'PowerShell/7/pwsh.exe')
        )
        $pwshPath=$candidates | Where-Object {Test-Path -LiteralPath $_ -PathType Leaf} | Select-Object -First 1
    }
    if (-not $pwshPath) {throw 'PowerShell 7 was not found on PATH or in the Codex runtime. Install PowerShell 7 or add pwsh.exe to PATH, then retry this command.'}
    $forwardArguments=@('-NoLogo','-NoProfile','-File',$PSCommandPath)
    foreach ($entry in $PSBoundParameters.GetEnumerator()) {
        if ($entry.Value -is [Management.Automation.SwitchParameter]) {
            if ($entry.Value.IsPresent) {$forwardArguments+=('-'+$entry.Key)}
        } else {$forwardArguments+=@(('-'+$entry.Key),([string]$entry.Value))}
    }
    & $pwshPath @forwardArguments
    if ($LASTEXITCODE -ne 0) {throw "Manual task failed in PowerShell 7 (exit $LASTEXITCODE). See the error above; no automatic retry was started."}
    return
}
if (-not $Root) { throw 'Supply -Root with the booking workspace path.' }
$Root=[IO.Path]::GetFullPath($Root).TrimEnd([char[]]'\/')
# Import the established verifier, approval and journal controls without executing a campaign.
$manualExecute=$Execute
. (Join-Path $Root 'scripts/start-development.ps1') -Root $Root -TaskId $TaskId -CodexCommand $CodexCommand | Out-Null
$Execute=$manualExecute
$context=Get-TaskContext $Root $TaskId -RequireReady
if ($context.Ledger.status -eq 'PASS') {throw 'Task is already accepted; choose the next dependency-ready task.'}
$control=Resolve-AutomationPath $Root 'docs/execution/runs/automatic'
[void][IO.Directory]::CreateDirectory($control)
$lock=$null
try {
    $lock=[IO.File]::Open((Join-Path $control 'controller.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    Recover-AutomationLedger $Root $control
    if ($Action -in @('Plan','Start','Verify','Finish') -and (-not $Execute -or -not $ExclusiveWriterConfirmed)) {
        throw 'This action requires -Execute -ExclusiveWriterConfirmed. Finish or stop any other booking implementation session first. The lock excludes the controller, but cannot identify unrelated interactive terminals.'
    }
    $directory=New-WorkflowDirectory $Root $null ('manual-'+$TaskId+'-'+$Action.ToLowerInvariant())
    $config=Read-WorkflowJson (Join-Path $Root 'contracts/automation.config.json')
    if (-not $PlanPath) {
        $PlanPath='docs/execution/runs/manual-plans/'+$TaskId+'.json'
        if ($TaskId -eq 'T01' -and -not (Test-Path (Join-Path $Root $PlanPath))) {
            $PlanPath='docs/execution/plans/T01.json'
        }
    }
    if ($Action -eq 'Plan') {
        $criteria=Get-AutomationTaskCriteria $Root $context.Task
        $paths=Get-AutomationTaskPaths $Root $context.Task
        $prompt="Read docs/prompts/SUPERVISOR.md, AGENTS.md and $($context.Task.specPath). Produce one complete task plan for $TaskId. Preserve these exact acceptance criteria: $($criteria | ConvertTo-Json -Compress). Allowed paths must be a subset of: $($paths | ConvertTo-Json -Compress). Use concrete verification scripts and criterion-specific fresh evidence paths. Retain all human/external gates. Split implementation into coherent slices but request review only after the whole task verifies or a repeated failure needs diagnosis. Read actual source and ledger. Do not edit any files."
        $run=Invoke-AutomationAgent -Root $Root -Role Plan -Prompt $prompt -SchemaPath (Join-Path $Root 'contracts/automation-plan.schema.json') -RunDirectory $directory -MaxRunSeconds 1800 -WindowsSandbox $config.windowsSandbox -CodexCommand $CodexCommand -ReadOnly
        if (-not $run.valid) {throw ($run.issues -join '; ')}
        Assert-AutomationPlan $Root $context.Task $run.result
        $destination=Resolve-AutomationPath $Root ('docs/execution/runs/manual-plans/'+$TaskId+'.json')
        Write-AutomationJson $destination $run.result
        [pscustomobject]@{taskId=$TaskId;planPath=$destination;implementationStarted=$false} | ConvertTo-Json
        return
    }
    $plan=Read-WorkflowJson (Resolve-AutomationPath $Root $PlanPath -MustExist)
    Assert-AutomationPlan $Root $context.Task $plan
    Write-NewJson (Join-Path $directory 'plan.json') $plan
    $prompt=@"
Implement only $TaskId in this workspace. Read AGENTS.md, docs/prompts/SUPERVISOR.md, $($context.Task.specPath), and $(Get-AutomationRelativePath $Root (Join-Path $directory 'plan.json')).
The owner now chooses each task manually. Do not start an automatic campaign, another task, or a second implementation writer. Continue useful partial work; no review is required after each slice. Request a focused GPT diagnosis after two failures with the same root cause. Review the complete task once all mandatory verification passes.
Preserve existing partial work and original documents. Write only the plan's allowed paths. Put scratch files and fixtures under docs/verification/$TaskId/, never at workspace root. Maven caches are build artifacts. Ledgers, next-step, source plans, feature packets, controller scripts and human acceptance records are read-only. You cannot approve yourself or mark PASS.
Perform sequential coherent slices until all planned behavior and checks are implemented, or report a concrete blocker. Use actual commands and retain sanitized logs, exits, timestamps and evidence. End with changed paths, checks and remaining work in plain text; no structured final JSON is required. Missing tools and failed checks must remain truthful. Preserve all acceptance criteria. The separate Finish action verifies and reviews before acceptance; never auto-advance.
"@
    Write-NewUtf8 (Join-Path $directory 'prompt.txt') $prompt
    if ($Action -eq 'Prepare') {
        [pscustomobject]@{taskId=$TaskId;dependencyReady=$true;promptPath=(Join-Path $directory 'prompt.txt');ledgerChanged=$false;reviewBoundary='Complete task only';automaticAdvance=$false} | ConvertTo-Json
        return
    }
    if ($Action -eq 'Start') {
        $cli=Get-CodexCommand $CodexCommand
        $arguments=@('--cd',$Root,'--sandbox','workspace-write','--ask-for-approval','never','--config',('windows.sandbox="'+$config.windowsSandbox+'"'))
        if ($Provider -eq 'lmstudio') {
            if (-not $Model) {throw 'LM Studio requires -Model with the exact served model ID. Use -Provider gpt for an explicit manual failover.'}
            $inventory=Get-LocalModelInventory lmstudio
            if (-not (@($inventory.models) -ccontains $Model)) {throw 'Model is not served by LM Studio; no automatic switch or download was attempted.'}
            $arguments+=@('--oss','--local-provider','lmstudio','--model',$Model)
        } else {
            $arguments+=@('--config','model_provider="openai"','--search')
            if ($Model) {$arguments+=@('--model',$Model)}
        }
        $before=Get-SourceSnapshot $Root
        Write-NewJson (Join-Path $directory 'before-source.json') $before
        Set-AutomationTaskLedger -Root $Root -ControlDirectory $control -TaskId $TaskId -Status IN_PROGRESS -IncrementAttempt -Notes 'Operator selected this interactive implementation session; no fixed implementation deadline or structured-final requirement.'
        $protected=Get-AutomationProtectedHashes $Root
        $arguments+=('Read '+(Get-AutomationRelativePath $Root (Join-Path $directory 'prompt.txt'))+' and carry out that task. Do not edit the prompt or plan.')
        $exitCode=-1
        try { & $cli.path @arguments; $exitCode=$LASTEXITCODE }
        finally {
            $after=Get-SourceSnapshot $Root
            $changed=@(Get-ChangedSourcePaths $before $after)
            $issues=@($changed | Where-Object {-not (Test-AutomationAllowedPath $_ $plan.allowedPaths)} | ForEach-Object {'Out-of-scope source change: '+$_})
            try {Assert-AutomationProtectedHashes $Root $protected} catch {$issues+= $_.Exception.Message}
            Write-NewJson (Join-Path $directory 'session.json') ([ordered]@{taskId=$TaskId;provider=$Provider;exitCode=$exitCode;sourceRevision=$after.revision;changedPaths=$changed;issues=$issues;accepted=$false})
            if ($exitCode -ne 0 -or $issues.Count) {
                Set-AutomationTaskLedger -Root $Root -ControlDirectory $control -TaskId $TaskId -Status BLOCKED -ReviewStatus CHANGES_REQUIRED -Notes ('Interactive session needs recovery: exit '+$exitCode+'; '+($issues -join '; '))
            }
        }
        if ($exitCode -ne 0 -or $issues.Count) {throw 'Session evidence preserved; inspect session.json. No review or next task was launched.'}
        Write-Host 'Session ended. Continue this task if incomplete; use Finish when the complete task is ready.'
        return
    }
    $verification=Invoke-AutomationVerification -Root $Root -Task $context.Task -Plan $plan -RunDirectory $directory -Config $config
    Write-NewJson (Join-Path $directory 'verification.json') $verification
    if (-not $verification.passed) {throw ('Verification failed; no GPT review launched: '+($verification.failureReasons -join '; '))}
    if ($Action -eq 'Verify') { $verification | ConvertTo-Json -Depth 8; return }
    $snapshot=Get-SourceSnapshot $Root
    $hashes=Get-AutomationEvidenceHashes $Root $verification.evidencePaths
    $reviewPrompt="Read docs/prompts/SUPERVISOR.md, $($context.Task.specPath), $(Get-AutomationRelativePath $Root (Join-Path $directory 'plan.json')) and $($verification.reportPath). Inspect actual source and all criterion evidence independently. Review complete task $TaskId, exact source revision $($snapshot.revision). Return APPROVE only if every original criterion is met and no material finding remains; otherwise REQUEST_CHANGES or BLOCKED. Do not edit any files. This is the single complete-task review, not a per-slice review."
    $review=Invoke-AutomationAgent -Root $Root -Role Review -Model $config.reviewModel -Prompt $reviewPrompt -SchemaPath (Join-Path $Root 'contracts/automation-review.schema.json') -RunDirectory (Join-Path $directory 'review') -MaxRunSeconds 1800 -WindowsSandbox $config.windowsSandbox -CodexCommand $CodexCommand -ReadOnly
    if (-not $review.valid) {throw ('GPT review failed; verified work is preserved: '+($review.issues -join '; '))}
    Assert-AutomationEvidenceHashes $Root $hashes
    Assert-AutomationApproval $Root $context.Task $plan $verification $review.result $snapshot.revision
    Assert-AutomationHumanGate $Root $context.Task $config
    $humanPaths=@()
    if ($TaskId -eq 'T30') {$humanPaths=@('docs/execution/manual-accessibility-acceptance.json')+@((Read-WorkflowJson (Join-Path $Root 'docs/execution/manual-accessibility-acceptance.json')).evidencePaths)}
    if ($TaskId -eq 'T42') {$humanPaths=@($config.ownerAcceptancePath)}
    $acceptanceHashes=Get-AutomationEvidenceHashes $Root (@($verification.evidencePaths)+@(Get-AutomationRelativePath $Root $review.runSummaryPath)+@(Get-AutomationRelativePath $Root (Join-Path $directory 'review/result.json'))+$humanPaths)
    $copies=Copy-AutomationAcceptanceEvidence $Root $acceptanceHashes (Join-Path $directory 'accepted-evidence')
    $acceptancePath=Join-Path $directory 'acceptance.json'
    Write-NewJson $acceptancePath ([ordered]@{taskId=$TaskId;sourceRevision=$snapshot.revision;acceptedAtUtc=[DateTime]::UtcNow.ToString('o');reviewApproved=$true;specSha256=(Get-FileHash (Join-Path $Root $context.Task.specPath) -Algorithm SHA256).Hash.ToLowerInvariant();evidence=$copies})
    Set-AutomationTaskLedger -Root $Root -ControlDirectory $control -TaskId $TaskId -Status PASS -ReviewStatus APPROVED -Revision $snapshot.revision -Evidence @(Get-AutomationRelativePath $Root $acceptancePath) -Notes 'Operator requested complete-task verification and separate GPT review. No next task launched.'
    [pscustomobject]@{taskId=$TaskId;status='PASS';acceptancePath=$acceptancePath;automaticAdvance=$false} | ConvertTo-Json
} finally { if ($lock) {$lock.Dispose()} }
