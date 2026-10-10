# Manual task development and recovery

The campaign stopped because its implementation exceeded 900 seconds and wrote `.t01-neg-exits.json` outside the allowed paths. A missing structured final result is a consequence of that timeout. Partial code and evidence remain available. This does not establish application acceptance or prove another terminal caused the failure.

The manual launcher automatically opens PowerShell 7 when called from Windows PowerShell 5.1. Finish or stop other Codex sessions that edit this booking folder before running implementation, verification or review. The controller lock prevents another cooperating launcher, but a plain terminal `codex` session does not acquire that lock. Multiple writers in this folder can overwrite files or invalidate verification and review fingerprints. The desktop app-server alone is not an implementation conflict. No recovery command kills unrelated processes.

## Workspace setup

Manual recovery is already installed in this repository. No installer from private run directories is required. From the repository root, set:

```powershell
$bookingRoot = (Get-Location).Path
```

Maven caches and private run outputs are ignored by Git. Automatic campaign execution is disabled. Original source documents, partial application code, ledgers and the reusable T01 plan are included. Historical evidence is not proof of current task acceptance.

## Run the selected task

Preview its instructions without starting a model:

```powershell
.\scripts\manual-task.ps1 -Root $bookingRoot -TaskId T01 -Action Prepare
```

Start interactive Codex using the exact LM Studio model ID served by the endpoint:

```powershell
.\scripts\manual-task.ps1 -Root $bookingRoot -TaskId T01 -Action Start -Provider lmstudio -Model 'qwen3.8-27b' -Execute -ExclusiveWriterConfirmed
```

Use that ID only if LM Studio actually serves it. If the local model is unavailable or inadequate, explicitly choose signed-in GPT Codex for the same task:

```powershell
.\scripts\manual-task.ps1 -Root $bookingRoot -TaskId T01 -Action Start -Provider gpt -Execute -ExclusiveWriterConfirmed
```

Start records IN_PROGRESS and increments the attempt count in both ledgers. It launches the interactive CLI with no implementation wall-clock deadline and no structured-final requirement. Continue sequential slices in this session. Exit when done or blocked. No mandatory review after each slice, automatic provider switch, next-task launch, model download or service restart occurs. Interrupted sessions retain their work. The snapshot and protected-file guards inspect changes after exit; they are process controls, not an OS path sandbox.

Run acceptance checks independently when useful:

```powershell
.\scripts\manual-task.ps1 -Root $bookingRoot -TaskId T01 -Action Verify -Execute -ExclusiveWriterConfirmed
```

When the whole task is ready, request verification and one separate GPT review in a single command:

```powershell
.\scripts\manual-task.ps1 -Root $bookingRoot -TaskId T01 -Action Finish -Execute -ExclusiveWriterConfirmed
```

Finish reruns real mandatory checks against current source. Failing or missing checks prevent review and PASS. Passing checks trigger a read-only GPT review with a 30-minute bounded review deadline. Approval must cover every original criterion, cite freshly hashed evidence and match the tested revision. T30 still requires actual manual accessibility evidence; T42 still requires owner acceptance. Only valid approval updates both ledgers to PASS/APPROVED and preserves immutable evidence copies. A review failure leaves the task unaccepted, with diagnostics preserved; repair the same task before retrying. No command advances automatically.

## Next task and plans

After T01 is accepted, manually select T02. For each new task, create its precise GPT work order once:

```powershell
.\scripts\manual-task.ps1 -Root $bookingRoot -TaskId T02 -Action Plan -Execute -ExclusiveWriterConfirmed
.\scripts\manual-task.ps1 -Root $bookingRoot -TaskId T02 -Action Prepare
```

Then use Start and Finish for that selected task. Repeat in manifest dependency order through T42. Plan is read-only and validates exact criteria, allowed paths, verification scripts and evidence mapping. T01 reuses its existing validated plan. A previously generated plan can be supplied with `-PlanPath` (workspace-relative). Incomplete dependencies block launching their dependents. After two repairs for the same cause, request a focused GPT diagnosis with the preserved reproduction rather than weakening acceptance.

Launcher validation is not application acceptance. At recovery preparation, T01 is BLOCKED with two attempts and zero accepted application tasks. Compatibility, clean build and secrets checks are still required before T02.
