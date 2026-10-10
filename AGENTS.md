# Booking application development contract

Build the application defined in the supplied Master Execution Plan v2. Read `README.md`, `docs/DEVELOPMENT_GOAL.md`, `docs/execution/next-step.md`, `contracts/tasks.json` and the task ledger before editing. The ledgers and actual verification evidence determine current progress; feature preparation-date labels are historical.

## Specification authority

1. Direct user instructions govern the work.
2. `Booking_Application_Master_Execution_Plan.md` v2 and `Booking_Application_Design_and_Development.docx` define whole-application scope. The Master's frontend extension supersedes the older backend-only exclusion.
3. `Booking_Backend_Local_Agent_Execution_Plan.md` supplies retained backend invariants, simulator behavior and V01–V26.
4. `docs/architecture/` supplies explicit adopted design decisions that fill missing support documents. Do not treat reconstructed requirements or schema as original supplied files.
5. `docs/features/Txx.md` bounds one implementation task. Report genuine conflicts instead of choosing weaker acceptance rules.

Use this workspace as the repository root. Do not create another nested `booking-platform` repository. Preserve original source documents and unrelated user work. Do not replace the startup scripts with application command stubs that report success.

## Roles and the task loop

The local Codex OSS model implements one dependency-ready task. GPT-backed Codex specifies and reviews it. Keep one implementation writer at a time; independent read-only reviews can run concurrently.

The owner now selects one task at a time manually through scripts/manual-task.ps1. This latest instruction supersedes unattended T01-T42 advancement. Use docs/MANUAL_DEVELOPMENT.md. Keep one implementation writer. Continue sequential slices within the selected task without reviewing every slice. Run mandatory verification and one separate GPT review when the complete task is ready. No automatic provider switch or next-task launch. Preserve every acceptance criterion and human gate. Only the supervisor/launcher updates ledgers; implementers cannot accept themselves.

- Begin with the actual Git status, toolchain and relevant feature/architecture contracts.
- A dependency is ready only when its ledger status is PASS, review is APPROVED and revision/evidence are recorded. T26 means T01–T25; it is a backend checkpoint.
- Read the packet, implement its bounded behavior and run meaningful acceptance checks. Verify a schema change with real PostgreSQL, never H2.
- Record commands, actual exit codes, timestamps, changed paths, tested revision, limitations and evidence in a task run report. Do not print secrets or capability tokens.
- Local implementers may report NEEDS_REVIEW, FAILED or BLOCKED. They must not promote themselves to PASS or alter accepted dependencies.
- The GPT supervisor reads the actual patch/source and relevant evidence, reviews security and behavior, and requests concrete fixes or records APPROVED. A clean-looking diff alone is insufficient.
- A PASS transition requires every mandatory task criterion to be tested and satisfied, evidence tied to the tested source, and APPROVED review. Missing external accounts may be NOT_RUN only for the explicitly separate live gates.
- After two repairs for the same failing root cause, produce `docs/execution/review-packets/Txx.md` with a minimal reproduction and ask GPT for a focused diagnosis. Do not weaken constraints to pass.
- Update both ledger views and `next-step.md` after accepted work. Present the next ready task for the operator to select; do not regenerate completed work.

Prompts and allowed paths are process controls, not an OS-level guarantee. Inspect the diff for unintended writes. The application tool gateway must enforce its own authorization independent of these development instructions.

## Non-negotiable application behavior

- Default free guest booking and management require no account, AI service or simulator availability. An explicitly selected simulated-deposit policy must report simulator pending/failure truthfully.
- PostgreSQL enforces tenant ownership, exclusive allocations and capacity; caches/model text are advisory.
- Approval is a scoped server record created through the authorized client action, bound to exact terms/hash/version and expiry. Models cannot issue their own approvals.
- Reservations and outbox commit together. Retries return durable idempotent results. Failed rescheduling preserves the original booking and allocation.
- AI produces validated data and trusted component selections; it cannot run arbitrary SQL, shell, infrastructure commands or generated page code through product tools.
- Simulator only: no payment SDK, card collection, payment credentials, charge or real refund. Label simulated receipts and values.
- Keep optional inference/providers separate from core booking availability. Never silently substitute fake runtime success.
- Dates use location IANA zones and UTC instants. Interpret gaps and overlaps explicitly.
- Paid cloud deployment, public publication and real-customer communications are not part of startup-pack execution. Prepare reviewable assets first; use only authorized environments during later deployment tasks.

## Toolchain and verification

Java 25, stable compatible Spring Boot 4.x, Maven wrapper, React/TypeScript, PostgreSQL, Valkey, Keycloak, Temporal, LocalStack SQS and Mailpit are the source baseline. Resolve actual compatible versions and checks in T01; do not fabricate a lock or use `latest` images. Application operator commands are implemented progressively in their assigned tasks and must fail if mandatory checks fail.

Read `docs/verification/VERIFICATION_MATRIX.md`. Distinguish app contracts, live local inference, external providers, Compose, kind, cloud templates, paid deployment, scale and P3 experiments. Startup-pack validation and a toy local-model trial are not application acceptance.
