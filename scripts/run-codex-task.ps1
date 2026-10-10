[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidatePattern('^T[0-9]{2}$')][string]$TaskId,
    [Parameter(Mandatory=$true)][ValidateSet('Local','Review')][string]$Role,
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Model,
    [ValidateSet('ollama','lmstudio')][string]$Provider,
    [string]$Root,
    [string]$ReviewPacketPath,
    [string]$OutputDirectory,
    [string]$CodexCommand='codex',
    [switch]$Execute,
    [switch]$DryRun,
    [ValidateRange(1,3600)][int]$MaxRunSeconds=300,
    [ValidateSet('mxc','elevated','unelevated')][string]$WindowsSandbox,
    [ValidateRange(1000,400000)][int]$MaxPromptChars=100000
)
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PSScriptRoot 'workflow-common.ps1')
if ($Execute -and $DryRun) { throw 'Choose -Execute or -DryRun, not both.' }
if ($Role -eq 'Local' -and -not $Provider) { throw 'Local requires an explicit -Provider ollama or lmstudio.' }
if ($Role -eq 'Review' -and $Provider) { throw 'GPT Review does not accept a local provider.' }
if ($Role -eq 'Review' -and $Model -notmatch '^gpt-') { throw 'Review requires an explicit GPT model ID beginning with gpt-. Availability is verified by the authenticated CLI request.' }
$context = Get-TaskContext $Root $TaskId -RequireReady
if ($Role -eq 'Local' -and $context.Ledger.status -eq 'PASS') { throw 'Task is already PASS; supervisor must reopen it before implementation.' }
$prompt = Get-TaskPrompt $Root $context $Role $ReviewPacketPath $MaxPromptChars
$schema = Resolve-WorkspacePath $Root $(if ($Role -eq 'Local') {'contracts/local-result.schema.json'} else {'contracts/review-result.schema.json'}) -MustExist
$sandbox = if ($Role -eq 'Local') {'workspace-write'} else {'read-only'}
$baseArgs = @('exec','--model',$Model,'--sandbox',$sandbox,'--cd',[IO.Path]::GetFullPath($Root),'--skip-git-repo-check','--ephemeral','--output-schema',$schema,'--color','never')
if ($Role -eq 'Local') { $baseArgs += @('--oss','--local-provider',$Provider) }
else { $baseArgs += @('--config','model_provider="openai"') }
if ($WindowsSandbox) { $baseArgs += @('--config',('windows.sandbox="' + $WindowsSandbox + '"')) }
if (-not $Execute) {
    [pscustomobject]@{ taskId=$TaskId; role=$Role; dryRun=$true; model=$Model; provider=$Provider; sandbox=$sandbox; maxRunSeconds=$MaxRunSeconds; arguments=$baseArgs + @('--output-last-message','<new-run-folder>/result.json','-'); promptCharacters=$prompt.Length; executionRequires='Explicit -Execute; supported CLI flags; working Windows sandbox; local endpoint exact model inventory for Local; unchanged revision for Review'; writesFiles=$false; ledgerChanged=$false } | ConvertTo-Json -Depth 10
    return
}
$cli = Get-CodexCommand $CodexCommand
$inventory = $null
if ($Role -eq 'Local') {
    $inventory = Get-LocalModelInventory $Provider
    if (-not (@($inventory.models) -ccontains $Model)) { throw "Model '$Model' is not in the exact $Provider endpoint inventory. No download or fallback will be attempted." }
}
$before = Get-SourceSnapshot $Root
$packet = $null
if ($Role -eq 'Review') {
    $packet = Read-WorkflowJson (Resolve-WorkspacePath $Root $ReviewPacketPath -MustExist)
    if ($packet.taskId -ne $TaskId -or $packet.sourceRevision -ne $before.revision) { throw 'Review packet task or source revision is stale. Rebuild the packet before review.' }
    Assert-PacketEvidence $Root $packet
}
$directory = New-WorkflowDirectory $Root $OutputDirectory ($TaskId + '-' + $Role.ToLowerInvariant())
$resultPath = Join-Path $directory 'result.json'
$argsForRun = $baseArgs + @('--output-last-message',$resultPath,'-')
Write-NewUtf8 (Join-Path $directory 'prompt.txt') $prompt
Write-NewJson (Join-Path $directory 'before-source.json') $before
Write-NewJson (Join-Path $directory 'invocation.json') ([ordered]@{ taskId=$TaskId; role=$Role; model=$Model; provider=$Provider; codex=$cli; arguments=$argsForRun; startedAtUtc=[DateTime]::UtcNow.ToString('o'); inventory=$inventory; inputSource='prompt.txt piped to stdin'; reviewPacket=$ReviewPacketPath; maxRunSeconds=$MaxRunSeconds; windowsSandbox=$WindowsSandbox })
$ledgerBefore = Get-LedgerFingerprint $Root
$exitCode = -1
$processResult = $null
$issues = New-Object 'System.Collections.Generic.List[string]'
try {
    $processResult = Invoke-BoundedCodex $cli.path $argsForRun (Join-Path $directory 'prompt.txt') $directory $MaxRunSeconds
    $exitCode = $processResult.exitCode
    if ($processResult.timedOut) { $issues.Add("Owned Codex invocation exceeded $MaxRunSeconds seconds and was stopped. Provider/model compatibility remains unverified.") }
} catch {
    $issues.Add($_.Exception.Message)
    if (-not (Test-Path -LiteralPath (Join-Path $directory 'codex.log'))) { Write-NewUtf8 (Join-Path $directory 'codex.log') $_.Exception.ToString() }
}
$after = Get-SourceSnapshot $Root
Write-NewJson (Join-Path $directory 'after-source.json') $after
if ((Get-LedgerFingerprint $Root) -ne $ledgerBefore) { $issues.Add('Agent modified a task ledger (JSON or Markdown); result rejected. Supervisor must inspect and restore ledger. No automatic restoration overwrites work.') }
if ($Role -eq 'Review' -and $after.revision -ne $before.revision) { $issues.Add('Source changed during read-only review; result rejected.') }
if ($Role -eq 'Review') {
    try { Assert-PacketEvidence $Root $packet } catch { $issues.Add($_.Exception.Message) }
}
if ($exitCode -ne 0) { $issues.Add("Codex exited $exitCode; this is not a successful task attempt.") }
$parsed = $null
try {
    if (-not (Test-Path -LiteralPath $resultPath)) { throw 'Codex did not produce result.json.' }
    $parsed = Read-WorkflowJson $resultPath
    Assert-ResultShape $parsed $Role $TaskId
    if ($Role -eq 'Local') {
        foreach ($path in @($parsed.changedFiles)) { [void](Resolve-WorkspacePath $Root $path) }
        foreach ($check in @($parsed.checks)) {
            foreach ($path in @($check.evidencePaths)) {
                if (Test-SensitivePath $path) { throw "Sensitive evidence path rejected: $path" }
                [void](Resolve-WorkspacePath $Root $path -MustExist)
            }
        }
    } else {
        if ($parsed.reviewedRevision -ne $before.revision) { throw 'Reviewer did not identify the exact source revision.' }
        if ($packet.purpose -eq 'DIAGNOSTIC' -and $parsed.decision -eq 'APPROVE') { throw 'Diagnostic packets cannot receive APPROVE; return BLOCKED or REQUEST_CHANGES with a concrete repair.' }
        foreach ($path in @($parsed.evidenceReviewed)) {
            if (Test-SensitivePath $path) { throw "Sensitive review evidence path rejected: $path" }
            [void](Resolve-WorkspacePath $Root $path -MustExist)
        }
        if ($parsed.decision -eq 'APPROVE' -and @($parsed.findings | Where-Object { $_.severity -in @('CRITICAL','HIGH','MEDIUM') }).Count -gt 0) { throw 'APPROVE contains unresolved material findings.' }
    }
} catch { $issues.Add($_.Exception.Message) }
$summary = [ordered]@{ taskId=$TaskId; role=$Role; cliExitCode=$exitCode; process=$processResult; wrapperValid=($issues.Count -eq 0); sourceRevisionBefore=$before.revision; sourceRevisionAfter=$after.revision; changedSourcePaths=@(Get-ChangedSourcePaths $before $after); resultPath=$resultPath; issues=$issues.ToArray(); ledgerChanged=($ledgerBefore -ne (Get-LedgerFingerprint $Root)); evidenceSemantics='Command exit and model report are captured. Feature tests require independent supervision. No task is promoted to PASS by this wrapper.' }
Write-NewJson (Join-Path $directory 'run-summary.json') $summary
$summary | ConvertTo-Json -Depth 10
if ($issues.Count -gt 0) { throw "Run rejected; inspect $directory/run-summary.json" }
