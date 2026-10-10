# Automatic application development

The unattended controller runs the T01–T42 development loop in this workspace. It uses an installed LM Studio model for implementation when the local provider is admitted and available. GPT-backed Codex defines each bounded work order, diagnoses failures and independently reviews the result. The user has authorized GPT implementation failover when local execution cannot proceed.

The controller is a development operator, not evidence that the application is complete. Existing code is preserved and reviewed against the [feature packets](FEATURE_CATALOG.md), [development goal](DEVELOPMENT_GOAL.md), [development contract](../AGENTS.md) and [verification matrix](verification/VERIFICATION_MATRIX.md).

## Run and inspect

Run these commands from `C:\Users\giree\OneDrive\Desktop\booking` in PowerShell:

```powershell
# Preview the current configuration and next eligible work without launching models.
.\scripts\start-development.ps1

# Run the configured tasks sequentially, starting or resuming from the ledger.
.\scripts\start-development.ps1 -Execute -Background

# Inspect the saved controller state and most recent outcome.
.\scripts\start-development.ps1 -Status
```

The same `-Execute -Background` command resumes after a stopped campaign. The hidden process records its owned PID and state. Omit `-Background` to run in the current terminal. Accepted tasks are validated and skipped. A second simultaneous controller is refused; only one implementation writer may operate in this workspace.

For a deliberately limited campaign:

```powershell
# Work on T01 only; normal prerequisite and acceptance rules still apply.
.\scripts\start-development.ps1 -Execute -TaskId T01

# Limit a campaign to one selected task.
.\scripts\start-development.ps1 -Execute -MaxTasks 1

# Use a different explicit configuration file or Codex executable.
.\scripts\start-development.ps1 -Execute -ConfigPath 'contracts/automation.config.json' -CodexCommand 'codex'
```

Default configuration is saved in `contracts/automation.config.json`. Change configured installed model IDs or execution budgets there before starting a new campaign. Each selected model ID must match the actual endpoint inventory. The workflow does not download a model or silently use a different provider.

Hosted Codex sessions enable live web search per invocation so planning/review can inspect current primary dependency documentation. This uses the official [Codex web-search configuration](https://learn.chatgpt.com/docs/config-file/config-reference); user configuration files are unchanged. Unavailable authoritative compatibility evidence remains a failed prerequisite rather than a generated citation.

## What happens automatically

1. The controller checks its configuration, workflow consistency, source preservation, accepted dependency evidence, available tools and Codex access. It records the observed environment and any failed probe.
2. It checks LM Studio state and local coding capability. An active unrelated generation is preserved. If local execution is unavailable, busy or fails its admission trial, the authorized GPT implementation route is selected and recorded. Idle service recovery and a verified portable Java environment may be prepared according to the configured environment policy.
3. It selects an unaccepted task whose dependencies have `PASS`, `APPROVED`, a tested revision and evidence. Tasks are processed one at a time according to the dependency graph; task count or numeric order cannot override a missing dependency.
4. A read-only GPT planner uses the exact numbered acceptance criteria to create a bounded implementation work order and verification plan. The controller records `IN_PROGRESS` and the real attempt count in both ledger views.
5. One local or GPT implementer makes the permitted changes and produces a structured handoff. Implementers cannot approve themselves, rewrite acceptance criteria or promote the task ledger.
6. The controller independently runs the planned checks with real subprocess exit codes, deadlines and evidence capture. PostgreSQL behavior requires real PostgreSQL. An absent executable, swallowed failure, missing evidence or mandatory `NOT_RUN` result cannot become acceptance.
7. A separate read-only GPT reviewer examines the current source, relevant tests, captured verification and criterion coverage. An approval applies only to the exact reviewed source and evidence. Source or evidence changes invalidate that approval before acceptance.
8. The controller records `PASS` and `APPROVED` only after all mandatory criteria are satisfied. It updates the JSON and Markdown ledgers together through a recoverable journal, updates `next-step.md`, and continues with the next ready task.

T01's earlier assessment-only session remains historical context. Automatic task planning may define the later compatibility, scaffold and clean-build sessions, but it must retain every parent acceptance criterion in [T01](features/T01.md). A successful inventory does not accept T01 or make T02 ready.

## Failover and stopping conditions

Each child process and task has a finite budget. Timeouts stop only the process tree owned by that invocation. Partial work, command results and diagnostic evidence are preserved. A timeout is a failed or incomplete attempt, never a successful transport result.

Repair sessions stay on the current task. Repeated failure at the same root cause triggers focused GPT diagnosis before further implementation. Local-provider failures may use the explicitly authorized GPT implementer; that implementer still needs independent verification and a separate GPT review. A failure of authenticated GPT access cannot be repaired by silently substituting an unreviewed local approval.

The controller checkpoints when a task's session or campaign budget is exhausted, a mandatory prerequisite cannot be restored, a protected file changes unexpectedly, another writer is detected, provider access fails, or required human evidence remains absent. Run `-Status` to inspect the precise reason and relevant evidence. Restarting with `-Execute` resumes from saved state and revalidates dependencies and evidence.

Protected materials include the original plans, feature acceptance, workflow contracts, controller protocols, progress records and owner-acceptance evidence. An implementation attempt that changes these without the controller's authorized phase is rejected. Source snapshots and process controls help detect unintended writes; they are not a guarantee that arbitrary model instructions provide operating-system isolation.

## Evidence and progress

Controller state, lock and ledger journal are under `docs/execution/runs/automatic/`. Unique campaign, launcher and test directories sit alongside it under `docs/execution/runs/`. Per-task check outputs are under `docs/verification/Txx/`; accepted output, review and human evidence is copied into the accepting session's `accepted-evidence/` directory and hashed. Later regression runs may refresh task output without replacing historical proof. These operational run records are ignored by Git by default. Preserve or export required evidence before removing run directories.

The durable progress views are:

- [Machine ledger](execution/task-ledger.json): status, review, attempts, revision and evidence.
- [Readable ledger](execution/task-ledger.md): synchronized task progress.
- [Next work order](execution/next-step.md): current bounded task and continuation instructions.

Provider availability, a valid JSON handoff and a passing preparation check are distinct from feature acceptance. The controller retains actual commands, exit codes, UTC timestamps, tested source fingerprints, evidence hashes, review decisions and unresolved limitations. Reports must identify whether implementation used LM Studio or GPT failover.

## Completing the application honestly

T26 verifies the backend checkpoint. T41 verifies the final application source and mandatory local release gates. External provider accounts, live inference, representative large-scale load and paid cloud deployment retain their separate readiness labels. Template validation does not authorize or prove a paid deployment.

T30 retains its keyboard and screen-reader verification requirements. Automated accessibility checks alone do not manufacture a manual checklist result. T42/H01 requires actual recorded owner acceptance of the final handoff. The controller can prepare the handbook and pilot evidence automatically, but it must leave acceptance pending until the owner has actually given it. General authorization to develop the application is not acceptance of an unseen final result.

These two human records are protected against child-agent writes even when absent. A real tester supplies `docs/execution/manual-accessibility-acceptance.json` with `taskId: T30`, `decision: VERIFIED`, `tester`, `environment`, `verifiedAtUtc`, strict JSON booleans `keyboardPassed: true` and `screenReaderPassed: true`, existing nonempty `evidencePaths`, and `reviewedProductRevision`. The owner supplies `docs/execution/owner-acceptance.json` with `taskId: T42`, `decision: ACCEPTED`, `owner`, `acceptedAtUtc` and `reviewedProductRevision`. Timestamps must be real ISO UTC values. Neither file is created automatically. To identify the product actually inspected, dot-source `scripts/start-development.ps1` without `-Execute` and run `Get-AutomationProductRevision -Root (Get-Location).Path`; it hashes source while excluding check outputs and the two acceptance records themselves. Changes to the inspected product invalidate the record.

Default bounds are 24 implementation sessions per task, 900 seconds per implementation/plan/review invocation, 900 seconds per verification command, two provider retries and a 24-hour campaign. Limits preserve an incomplete checkpoint; they never convert failures to acceptance. For a cooperative stop, create `docs/execution/runs/automatic/stop.request`; the controller stops between owned bounded sessions. Remove that request before resuming. An integrity failure, exhausted authenticated provider access or a missing human gate remains visible instead of being retried indefinitely.

The controller may report the overall goal complete only when all mandatory task criteria, final release gates and the actual handoff acceptance have evidence. Paid infrastructure, public publication, real-customer communications and real payment operations remain outside the authorized development workflow.
