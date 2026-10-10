# Booking application development startup pack

Build a guest booking website and business portal with a correct multi-tenant scheduler, then extend it with an owner-approved AI blueprint builder and optional intent booking. Use the installed local model through Codex OSS for bounded implementation tasks and GPT-backed Codex for specification, diagnosis and review.

The workspace contains design material, a development pack and an unreviewed Maven scaffold. The [live ledger](docs/execution/task-ledger.json) records accepted progress. Initial workstation observations are historical; the controller rechecks prerequisites at launch. **LM Studio is the selected local provider**, using installed models only. GPT plans, diagnoses and independently reviews each task, and provides implementation failover when the local model cannot complete a bounded session.

## Start here

Choose one task at a time from PowerShell in this folder. The launcher automatically opens PowerShell 7 when called from Windows PowerShell 5.1:

```powershell
.\scripts\manual-task.ps1 -Root (Get-Location).Path -TaskId T01 -Action Prepare
.\scripts\manual-task.ps1 -Root (Get-Location).Path -TaskId T01 -Action Start -Provider gpt -Execute -ExclusiveWriterConfirmed
```

The first command prepares instructions; the second starts the selected interactive task using signed-in GPT Codex. Finish or stop other implementation writers before starting. See [manual development](docs/MANUAL_DEVELOPMENT.md) for LM Studio implementation, explicit GPT failover and complete-task verification/review. The launcher never automatically advances to the next task. Automatic campaign execution is disabled by the current configuration. Existing code and historical logs are unreviewed; T01 remains incomplete until its original acceptance criteria pass.

The following commands remain available for individual assessment or supervised sessions:

1. Read [the definitive goal](docs/DEVELOPMENT_GOAL.md) and [plan analysis](docs/PLAN_ANALYSIS.md).
2. Read [the local model and GPT guide](docs/LOCAL_AI_AND_CODEX_GUIDE.md), run the doctor, and complete the bounded model capability trial.
3. Read [T01](docs/features/T01.md), prepare its packet, and establish the real application build baseline.
4. Ask GPT-backed Codex to review the task patch and evidence. Update the ledger only after acceptance; continue with the next dependency-ready feature.

From PowerShell in this folder:

```powershell
.\scripts\agent-doctor.ps1
.\scripts\verify-workflow.ps1
.\scripts\prepare-task.ps1 -TaskId T01 -DryRun
.\scripts\run-codex-task.ps1 -TaskId T01 -Role Local -Provider lmstudio -Model 'qwen3.8-flash-next' -WindowsSandbox mxc -DryRun
```

The last command previews an individual invocation. Its historical model ID is not a coding-quality recommendation. These individual startup wrappers do not install prerequisites or establish application acceptance; use the manual launcher for current task execution.

## Artifact map

| Artifact | Purpose |
| --- | --- |
| [AGENTS.md](AGENTS.md) | Shared development rules and model roles |
| [Automatic development](docs/AUTOMATIC_DEVELOPMENT.md), [controller](scripts/start-development.ps1) and [configuration](contracts/automation.config.json) | Sequential execution, real verification, GPT failover and resumable recovery |
| [Feature catalog](docs/FEATURE_CATALOG.md) and [task index](contracts/tasks.json) | Exact T01–T42 scope, dependencies and feature packets |
| [System design](docs/architecture/SYSTEM_DESIGN.md) | Deployables, boundaries and architecture decisions |
| [Domain contract](docs/architecture/DOMAIN_CONTRACT.md) | Ownership, state, transactions and scheduler invariants |
| [API contract](docs/architecture/API_CONTRACT.md) | Typed operation and error baseline |
| [Blueprint contract](docs/architecture/BLUEPRINT_CONTRACT.md) | Trusted configuration and publication rules |
| [Blueprint schema](contracts/booking-blueprint.schema.json) and [salon example](examples/salon.blueprint.json) | Portable synthetic starter artifacts |
| [Verification matrix](docs/verification/VERIFICATION_MATRIX.md) | V01–V26 plus reconstructed A01–A20 and traceability |
| [Progress ledger](docs/execution/task-ledger.md) and [machine ledger](docs/execution/task-ledger.json) | Accepted progress and review status |
| [Next step](docs/execution/next-step.md) and [decisions](docs/execution/decisions.md) | Continuation and unresolved inputs |
| [Supervisor](docs/prompts/SUPERVISOR.md), [repair](docs/prompts/REPAIR.md), [continuation](docs/prompts/CONTINUE.md) | GPT and local-model work orders |
| [Initial assessment](docs/execution/repository-assessment.md) | Actual repository and workstation starting state |
| [Startup validation](docs/verification/startup/STARTUP_VALIDATION.md) | Preparation checks and local-model trial results |

Original plans are preserved. The master v2 supersedes the backend-only frontend exclusion. Missing support-pack artifacts are reconstructed and labelled; original R01–R30 definitions were not supplied. Source hashes and extracted Word text are in `docs/sources/`.

No application is described as production-ready. Real payments remain excluded; live providers, inference, cloud deployment, large-scale capacity and experimental features receive separate evidence labels.
