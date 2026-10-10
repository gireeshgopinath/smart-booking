Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'workflow-common.ps1')

function Resolve-AutomationPath {
    param([string]$Root, [string]$Path, [switch]$MustExist)
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd([char[]]'\/')
    $candidate = if ([IO.Path]::IsPathRooted($Path)) { [IO.Path]::GetFullPath($Path) } else { [IO.Path]::GetFullPath((Join-Path $rootFull $Path)) }
    if (-not $candidate.StartsWith($rootFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "Path escapes workspace: $Path" }
    $cursor = $candidate
    while ($cursor -and $cursor.Length -ge $rootFull.Length) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse path is not allowed: $Path" }
        }
        if ($cursor -eq $rootFull) { break }
        $cursor = Split-Path -Parent $cursor
    }
    if ($MustExist -and -not (Test-Path -LiteralPath $candidate)) { throw "Missing workspace file: $Path" }
    return $candidate
}

function Get-AutomationRelativePath {
    param([string]$Root, [string]$Path)
    $full = Resolve-AutomationPath $Root $Path
    return $full.Substring([IO.Path]::GetFullPath($Root).TrimEnd([char[]]'\/').Length + 1).Replace('\','/')
}

function Write-AutomationJson {
    param([string]$Path, $Value)
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    $temporary = $Path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 40), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Protect-AutomationText {
    param([string]$Text)
    $Text = [regex]::Replace($Text, '(?im)((?:authorization|password|passwd|api[_-]?key|access[_-]?token|client[_-]?secret)\s*[:=]\s*)(?:bearer\s+)?[^\s,;]+', '$1[REDACTED]')
    return [regex]::Replace($Text, '(?i)\b(sk-[A-Za-z0-9_-]{12,}|gh[pousr]_[A-Za-z0-9_]{12,})\b', '[REDACTED_TOKEN]')
}

function Get-AutomationProtectedHashes {
    param([string]$Root)
    $paths = @('AGENTS.md','docs/DEVELOPMENT_GOAL.md','docs/verification/VERIFICATION_MATRIX.md','contracts/tasks.json','contracts/local-result.schema.json','contracts/review-result.schema.json','contracts/automation.config.json','contracts/automation-plan.schema.json','contracts/automation-review.schema.json','docs/sources/source-manifest.json','docs/execution/task-ledger.json','docs/execution/task-ledger.md','docs/execution/next-step.md','docs/execution/owner-acceptance.json','docs/execution/manual-accessibility-acceptance.json')
    foreach ($directory in @('docs/features','docs/prompts')) {
        $directoryPath = Join-Path $Root $directory
        if (Test-Path -LiteralPath $directoryPath) { $paths += @(Get-ChildItem -LiteralPath $directoryPath -File | ForEach-Object { Get-AutomationRelativePath $Root $_.FullName }) }
    }
    $paths += @('scripts/automation-core.ps1','scripts/automation-environment.ps1','scripts/automation-verification.ps1','scripts/start-development.ps1','scripts/workflow-common.ps1','scripts/run-codex-task.ps1','scripts/build-review-packet.ps1','scripts/verify-workflow.ps1')
    $manifestPath = Join-Path $Root 'docs/sources/source-manifest.json'
    if (Test-Path -LiteralPath $manifestPath) { $paths += @((Read-WorkflowJson $manifestPath).sources | ForEach-Object { $_.path }) }
    $paths += @('docs/execution/runs/automatic/state.json','docs/execution/runs/automatic/events.jsonl','docs/execution/runs/automatic/ledger-transaction.json')
    $statePath=Join-Path $Root 'docs/execution/runs/automatic/state.json'
    if (Test-Path -LiteralPath $statePath) {
        $state=Read-WorkflowJson $statePath
        foreach ($record in @($state.acceptedTasks)) {
            $paths += $record.acceptancePath
            $acceptedPath=Resolve-AutomationPath $Root $record.acceptancePath -MustExist
            $paths += @((Read-WorkflowJson $acceptedPath).evidence | ForEach-Object {$_.path})
        }
        if ($state.campaignDirectory) {
            $campaignPath=Resolve-AutomationPath $Root $state.campaignDirectory -MustExist
            foreach ($taskDirectory in @(Get-ChildItem -LiteralPath $campaignPath -Directory | Where-Object {$_.Name -match '^T[0-9]{2}$'})) {
                $paths += Get-AutomationRelativePath $Root (Join-Path $taskDirectory.FullName 'plan.json')
                foreach ($sessionDirectory in @(Get-ChildItem -LiteralPath $taskDirectory.FullName -Directory | Where-Object {$_.Name -match '^session-[0-9]+$'})) {
                    $paths += Get-AutomationRelativePath $Root (Join-Path $sessionDirectory.FullName 'review-packet.json')
                }
            }
        }
    }
    $hashes = @{}
    foreach ($path in ($paths | Sort-Object -Unique)) {
        $full = Resolve-AutomationPath $Root $path
        $hashes[$path] = if (Test-Path -LiteralPath $full -PathType Leaf) { (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant() } else { 'ABSENT' }
    }
    return $hashes
}

function Assert-AutomationProtectedHashes {
    param([string]$Root, $Before)
    $after = Get-AutomationProtectedHashes $Root
    foreach ($path in $Before.Keys) { if ($after[$path] -cne $Before[$path]) { throw "Protected controller/specification/progress file changed: $path" } }
}

function Invoke-AutomationCommand {
    param([string]$Root, [string]$Command, [string[]]$Arguments=@(), [string]$RunDirectory, [int]$MaxRunSeconds=900)
    [void][IO.Directory]::CreateDirectory($RunDirectory)
    $requestPath = Join-Path $RunDirectory 'command-request.json'
    $helperPath = Join-Path $RunDirectory 'invoke-command.ps1'
    if (Test-Path -LiteralPath $requestPath) { throw 'Each command needs a fresh log directory.' }
    Write-NewJson $requestPath ([ordered]@{root=$Root;command=$Command;arguments=@($Arguments)})
    Write-NewUtf8 $helperPath @'
param([string]$RequestPath)
$ErrorActionPreference = 'Stop'
$request = Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json
Set-Location -LiteralPath $request.root
$global:LASTEXITCODE = 0
try {
    $ErrorActionPreference = 'Continue'
    $nativeArguments = @($request.arguments)
    & $request.command @nativeArguments 2>&1 | ForEach-Object { [Console]::Out.WriteLine($_.ToString()) }
    exit $LASTEXITCODE
} catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }
'@
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $start.Arguments = '-NoLogo -NoProfile -NonInteractive -File "' + $helperPath.Replace('"','\"') + '" -RequestPath "' + $requestPath.Replace('"','\"') + '"'
    $start.UseShellExecute = $false; $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $timedOut = $false
    try {
        if (-not $process.Start()) { throw 'Failed to launch owned command.' }
        $ownedPid = $process.Id
        $stdout = $process.StandardOutput.ReadToEndAsync(); $stderr = $process.StandardError.ReadToEndAsync()
        $heartbeat = 0
        while (-not $process.WaitForExit(500)) {
            if ($watch.Elapsed.TotalSeconds -ge $MaxRunSeconds) {
                $timedOut = $true
                if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { & taskkill.exe /PID $ownedPid /T /F 2>&1 | Out-Null } else { $process.Kill() }
                if (-not $process.WaitForExit(10000)) { throw 'Owned command could not be terminated.' }
                break
            }
            if ($watch.Elapsed.TotalSeconds -ge ($heartbeat + 30)) { Write-Host ('[{0:u}] command still running ({1}s): {2}' -f [DateTime]::UtcNow,[int]$watch.Elapsed.TotalSeconds,(Split-Path -Leaf $Command)); $heartbeat = [int]$watch.Elapsed.TotalSeconds }
        }
        $stdoutPath = Join-Path $RunDirectory 'stdout.log'; $stderrPath = Join-Path $RunDirectory 'stderr.log'
        Write-NewUtf8 $stdoutPath $stdout.GetAwaiter().GetResult()
        Write-NewUtf8 $stderrPath $stderr.GetAwaiter().GetResult()
        return [pscustomobject]@{exitCode=$(if ($timedOut) {124} else {$process.ExitCode});timedOut=$timedOut;ownedPid=$ownedPid;stdoutPath=$stdoutPath;stderrPath=$stderrPath;evidencePaths=@($stdoutPath,$stderrPath);durationSeconds=$watch.Elapsed.TotalSeconds}
    } finally { $process.Dispose() }
}

function Invoke-AutomationAgent {
    param([string]$Root,[ValidateSet('Plan','Implement','Review','Diagnose','Admission')][string]$Role,[string]$Model,[string]$Provider,[string]$Prompt,[string]$SchemaPath,[string]$RunDirectory,[int]$MaxRunSeconds=900,[string]$WindowsSandbox='mxc',[string]$CodexCommand='codex',[switch]$ReadOnly,[string[]]$AllowedPaths=@())
    [void][IO.Directory]::CreateDirectory($RunDirectory)
    $cli = Get-CodexCommand $CodexCommand
    $sandbox = if ($ReadOnly -or $Role -in @('Plan','Review','Diagnose')) {'read-only'} else {'workspace-write'}
    $arguments = @('exec','--sandbox',$sandbox,'--cd',[IO.Path]::GetFullPath($Root),'--skip-git-repo-check','--ephemeral','--json','--color','never','--config','approval_policy="never"','--output-schema',[IO.Path]::GetFullPath($SchemaPath),'--output-last-message',(Join-Path $RunDirectory 'result.json'))
    if ($Model) { $arguments += @('--model',$Model) }
    if ($Provider) {
        if (-not $Model) { throw 'A local provider needs an exact model ID.' }
        $inventory = Get-LocalModelInventory $Provider
        if (-not (@($inventory.models) -ccontains $Model)) { throw 'Requested local model is not served; no model download is permitted.' }
        $arguments += @('--oss','--local-provider',$Provider)
    } else { $arguments += @('--config','model_provider="openai"','--config','web_search="live"') }
    if ($WindowsSandbox) { $arguments += @('--config',('windows.sandbox="' + $WindowsSandbox + '"')) }
    $arguments += '-'
    Write-NewUtf8 (Join-Path $RunDirectory 'prompt.txt') $Prompt
    $before = Get-SourceSnapshot $Root
    $protected = Get-AutomationProtectedHashes $Root
    $issues = New-Object 'System.Collections.Generic.List[string]'
    $processResult = $null; $result = $null
    try {
        $processResult = Invoke-BoundedCodex $cli.path $arguments (Join-Path $RunDirectory 'prompt.txt') $RunDirectory $MaxRunSeconds
        if ($processResult.exitCode -ne 0) { $issues.Add("Codex exited $($processResult.exitCode); timedOut=$($processResult.timedOut)") }
        if (-not (Test-Path -LiteralPath (Join-Path $RunDirectory 'result.json'))) { throw 'No structured final result was produced.' }
        $result = Read-WorkflowJson (Join-Path $RunDirectory 'result.json')
        Assert-SchemaValue $result (Read-WorkflowJson $SchemaPath) '$'
    } catch { $issues.Add($_.Exception.Message) }
    $after = Get-SourceSnapshot $Root
    try { Assert-AutomationProtectedHashes $Root $protected } catch { $issues.Add($_.Exception.Message) }
    $changed = @(Get-ChangedSourcePaths $before $after)
    if ($sandbox -eq 'read-only' -and $changed.Count -gt 0) { $issues.Add('Read-only agent changed source files.') }
    if ($AllowedPaths.Count -gt 0) {
        foreach ($path in $changed) { if (-not (Test-AutomationAllowedPath $path $AllowedPaths)) { $issues.Add("Out-of-scope source change: $path") } }
    }
    $summary = [ordered]@{role=$Role;model=$Model;provider=$(if ($Provider) {$Provider} else {'openai'});sandbox=$sandbox;valid=($issues.Count -eq 0);process=$processResult;sourceRevisionBefore=$before.revision;sourceRevisionAfter=$after.revision;changedSourcePaths=$changed;issues=$issues.ToArray();resultPath=(Join-Path $RunDirectory 'result.json')}
    Write-NewJson (Join-Path $RunDirectory 'before-source.json') $before
    Write-NewJson (Join-Path $RunDirectory 'after-source.json') $after
    Write-NewJson (Join-Path $RunDirectory 'run-summary.json') $summary
    return [pscustomobject]@{valid=$summary.valid;result=$result;runSummaryPath=(Join-Path $RunDirectory 'run-summary.json');sourceRevisionBefore=$before.revision;sourceRevisionAfter=$after.revision;issues=$summary.issues;evidencePaths=@((Join-Path $RunDirectory 'run-summary.json'),(Join-Path $RunDirectory 'result.json'));changedSourcePaths=$changed}
}

function Test-AutomationAllowedPath {
    param([string]$Path,[string[]]$AllowedPaths)
    $normalized = $Path.Replace('\','/')
    foreach ($allowed in $AllowedPaths) {
        $allowed = $allowed.Replace('\','/').Trim()
        if ($allowed.EndsWith('/')) { if ($normalized.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)) { return $true } }
        elseif ($allowed.Contains('*')) { if ($normalized -like $allowed) { return $true } }
        elseif ($normalized -ieq $allowed) { return $true }
    }
    return $false
}

function Get-AutomationTaskCriteria {
    param([string]$Root,$Task)
    $text = Get-BoundedText $Root $Task.specPath 100000
    $match = [regex]::Match($text,'(?ms)^## Acceptance and expected checks\s*\r?\n(.*?)(?=^## |\z)')
    if (-not $match.Success) { throw 'Task acceptance section is missing.' }
    $criteria = @([regex]::Matches($match.Groups[1].Value,'(?m)^\d+\. (.+)$') | ForEach-Object { $_.Groups[1].Value.Trim() })
    if ($criteria.Count -eq 0) { throw 'Task has no numbered acceptance criteria.' }
    return ,$criteria
}

function Get-AutomationTaskPaths {
    param([string]$Root,$Task)
    $text = Get-BoundedText $Root $Task.specPath 100000
    $match = [regex]::Match($text,'(?m)^Planned allowed paths: (.+)$')
    if (-not $match.Success) { throw 'Task allowed-path contract is missing.' }
    $paths = @([regex]::Matches($match.Groups[1].Value,'`([^`]+)`') | ForEach-Object { ($_.Groups[1].Value -replace '\s*\(.*\)$','').Trim() })
    $paths = @($paths | ForEach-Object {
        if ($_ -eq 'Makefile or documented cross-platform mapping') {'Makefile'}
        elseif ($_ -eq 'package-lock.json or ADR-selected pinned lockfile') {'package-lock.json'}
        else {$_}
    })
    $paths += @(('docs/verification/' + $Task.id + '/'), ('docs/execution/review-packets/' + $Task.id + '.md'),('scripts/verify/verify-' + $Task.id + '.ps1'))
    return ,@($paths | Sort-Object -Unique)
}

function Assert-AutomationPlan {
    param([string]$Root,$Task,$Plan)
    Assert-SchemaValue $Plan (Read-WorkflowJson (Join-Path $Root 'contracts/automation-plan.schema.json')) '$'
    if ($Plan.taskId -ne $Task.id -or @($Plan.steps).Count -eq 0 -or @($Plan.verificationScripts).Count -eq 0) { throw 'Plan lacks correct task, steps or verification.' }
    $criteria = Get-AutomationTaskCriteria $Root $Task
    if (@($Plan.acceptanceMapping).Count -ne $criteria.Count) { throw 'Plan must cover every original task criterion.' }
    for ($index=0; $index -lt $criteria.Count; $index++) {
        if ($Plan.acceptanceMapping[$index].criterion -cne $criteria[$index] -or @($Plan.acceptanceMapping[$index].evidenceExpected).Count -eq 0) { throw 'Plan weakened/changed a criterion or omitted its evidence.' }
        foreach ($path in @($Plan.acceptanceMapping[$index].evidenceExpected)) { [void](Resolve-AutomationPath $Root $path); if (Test-SensitivePath $path) { throw 'Sensitive evidence path is forbidden.' } }
    }
    $allowed = Get-AutomationTaskPaths $Root $Task
    foreach ($path in @($Plan.allowedPaths)) {
        if (-not (Test-AutomationAllowedPath $path $allowed)) { throw "Plan expands task write scope: $path" }
        [void](Resolve-AutomationPath $Root $path)
    }
    foreach ($path in @($Plan.verificationScripts)) {
        if ($path -notmatch '^(scripts/verify/|tests/).+\.ps1$' -or -not (Test-AutomationAllowedPath $path $Plan.allowedPaths)) { throw 'Verification must be an explicitly allowed workspace test script.' }
    }
}

function Recover-AutomationLedger {
    param([string]$Root,[string]$ControlDirectory)
    $journalPath = Join-Path $ControlDirectory 'ledger-transaction.json'
    if (-not (Test-Path -LiteralPath $journalPath)) { return }
    $journal = Read-WorkflowJson $journalPath
    if ($journal.committed) {
        foreach ($record in @($journal.files)) {
            if ([IO.File]::ReadAllText((Resolve-AutomationPath $Root $record.path -MustExist)) -cne $record.after) {throw 'Ledger integrity changed outside the committed controller transaction; preserving all files for supervisor review.'}
        }
        return
    }
    foreach ($record in @($journal.files)) {
        $path = Resolve-AutomationPath $Root $record.path -MustExist
        $current = [IO.File]::ReadAllText($path)
        if ($current -cne $record.before -and $current -cne $record.after) { throw 'Unrelated ledger edit conflicts with interrupted transaction; preserving all files.' }
    }
    foreach ($record in @($journal.files)) { [IO.File]::WriteAllText((Resolve-AutomationPath $Root $record.path),$record.after,(New-Object Text.UTF8Encoding($false))) }
    $journal.committed = $true
    Write-AutomationJson $journalPath $journal
}

function Set-AutomationTaskLedger {
    param([string]$Root,[string]$ControlDirectory,[string]$TaskId,[string]$Status,[string]$ReviewStatus='PENDING',[switch]$IncrementAttempt,[string]$Revision,[string[]]$Evidence=@(),[string]$Notes)
    Recover-AutomationLedger $Root $ControlDirectory
    $jsonPath = Resolve-AutomationPath $Root 'docs/execution/task-ledger.json' -MustExist
    $mdPath = Resolve-AutomationPath $Root 'docs/execution/task-ledger.md' -MustExist
    $jsonBefore = [IO.File]::ReadAllText($jsonPath); $mdBefore = [IO.File]::ReadAllText($mdPath)
    $ledger = $jsonBefore | ConvertFrom-Json
    $row = @($ledger.tasks | Where-Object {$_.id -eq $TaskId})
    if ($row.Count -ne 1) { throw 'Ledger task must occur exactly once.' }
    if ($Status -eq 'PASS' -and ($ReviewStatus -ne 'APPROVED' -or -not $Revision -or $Evidence.Count -eq 0)) { throw 'PASS requires actual approval, revision and evidence.' }
    $row[0].status=$Status; $row[0].reviewStatus=$ReviewStatus
    if ($IncrementAttempt) {$row[0].attempts=[int]$row[0].attempts+1}
    $row[0].revision=$(if ($Revision) {$Revision} else {$null})
    if ($Evidence.Count -gt 0) {$row[0].evidence=@(@($row[0].evidence)+$Evidence | Sort-Object -Unique)}
    $row[0].notes=$Notes; $ledger.updatedAt=[DateTime]::UtcNow.ToString('o')
    $lines = New-Object 'System.Collections.Generic.List[string]'; $found=$false
    foreach ($line in ($mdBefore -split '\r?\n')) {
        if ($line -match ('^\| '+$TaskId+' \|')) {
            $cells=@($line.Split('|') | ForEach-Object {$_.Trim()})
            if ($cells.Count -ne 9) {throw 'Markdown ledger needs the Attempts column.'}
            $cells[4]=$Status; $cells[5]=[string]$row[0].attempts; $cells[6]=$ReviewStatus; $cells[7]=$(if ($row[0].evidence.Count) {$row[0].evidence -join '; '} else {'none'})
            $lines.Add('| '+($cells[1..7] -join ' | ')+' |'); $found=$true
        } elseif ($line.StartsWith('Original application baseline on ') -or $line.StartsWith('Application baseline on ') -or $line.StartsWith('Controller update:')) {
            $passCount=@($ledger.tasks | Where-Object {$_.status -eq 'PASS'}).Count
            $lines.Add("Controller update: $($ledger.updatedAt). $passCount / $($ledger.tasks.Count) tasks accepted. Current task $TaskId is $Status, attempt $($row[0].attempts), review $ReviewStatus. task-ledger.json is authoritative; this table is synchronized in the same journaled transaction. Preparation, code generation and mocks do not establish application acceptance.")
        } else {$lines.Add($line)}
    }
    if (-not $found) {throw 'Markdown ledger task was not found.'}
    $jsonAfter=($ledger | ConvertTo-Json -Depth 30)+[Environment]::NewLine
    $mdAfter=($lines -join [Environment]::NewLine).TrimEnd()+[Environment]::NewLine
    $journal=[ordered]@{committed=$false;taskId=$TaskId;createdAtUtc=[DateTime]::UtcNow.ToString('o');files=@([ordered]@{path='docs/execution/task-ledger.json';before=$jsonBefore;after=$jsonAfter},[ordered]@{path='docs/execution/task-ledger.md';before=$mdBefore;after=$mdAfter})}
    if ([IO.File]::ReadAllText($jsonPath) -cne $jsonBefore -or [IO.File]::ReadAllText($mdPath) -cne $mdBefore) {throw 'Concurrent ledger edit detected.'}
    Write-AutomationJson (Join-Path $ControlDirectory 'ledger-transaction.json') $journal
    [IO.File]::WriteAllText($jsonPath,$jsonAfter,(New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText($mdPath,$mdAfter,(New-Object Text.UTF8Encoding($false)))
    $journal.committed=$true
    Write-AutomationJson (Join-Path $ControlDirectory 'ledger-transaction.json') $journal
}

function Assert-AutomationApproval {
    param([string]$Root,$Task,$Plan,$Verification,$Review,[string]$SourceRevision)
    Assert-SchemaValue $Review (Read-WorkflowJson (Join-Path $Root 'contracts/automation-review.schema.json')) '$'
    if (-not $Verification.passed -or $Review.taskId -ne $Task.id -or $Review.decision -ne 'APPROVE' -or -not $Review.taskComplete -or $Review.reviewedRevision -cne $SourceRevision) {throw 'Real verification and exact-revision complete approval are required.'}
    if (@($Review.findings | Where-Object {$_.severity -in @('CRITICAL','HIGH','MEDIUM')}).Count -gt 0) {throw 'Approval has unresolved material findings.'}
    $criteria=Get-AutomationTaskCriteria $Root $Task
    if (@($Review.criteria).Count -ne $criteria.Count) {throw 'Approval does not cover every acceptance criterion.'}
    foreach ($criterion in $criteria) {
        $covered=@($Review.criteria | Where-Object {$_.criterion -ceq $criterion})
        if ($covered.Count -ne 1 -or -not $covered[0].passed -or @($covered[0].evidencePaths).Count -eq 0) {throw 'A required criterion lacks passing evidence.'}
        foreach ($path in @($covered[0].evidencePaths)) {
            $full=Resolve-AutomationPath $Root $path -MustExist
            if ((Get-Item -LiteralPath $full).PSIsContainer -or (Get-Item -LiteralPath $full).Length -eq 0 -or (Test-SensitivePath $path)) {throw 'Invalid criterion evidence.'}
            $relative=Get-AutomationRelativePath $Root $full
            if (-not (@($Verification.evidencePaths | ForEach-Object {Get-AutomationRelativePath $Root $_}) -contains $relative)) {throw 'Criterion cites evidence outside the independently verified and hashed evidence set.'}
            $mapping=@($Plan.acceptanceMapping | Where-Object {$_.criterion -ceq $criterion})
            if (-not (@($mapping[0].evidenceExpected | ForEach-Object {Get-AutomationRelativePath $Root $_}) -contains $relative)) {throw 'Criterion evidence is not in its declared verification mapping.'}
        }
    }
    if ((Get-SourceSnapshot $Root).revision -cne $SourceRevision) {throw 'Source changed after verification/review.'}
}
