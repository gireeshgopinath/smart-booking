# Definitive application development goal

Decision baseline dated 10 October 2026. Deliver a working multi-tenant booking application that a business can configure through a portal or an AI-generated, owner-approved blueprint. A guest can choose real availability, approve exact terms, book without registration, and securely manage the booking. A local model implements bounded features through Codex OSS; GPT-backed Codex guides the design and independently reviews evidence after every task.

The project begins with a synthetic salon and class provider. The launch market and commercial pilot remain owner decisions. Build the full T01–T42 scope from the master plan, with separate release readiness for the stages below.

## Measurable outcomes

| Stage | Deliverable | Completion evidence |
| --- | --- | --- |
| Development foundation | Pinned compatible toolchain, wrappers, real dependency setup, schemas and ledger | T01–T05 accepted; clean build, identity boundaries and PostgreSQL invariant tests |
| P0 core | Guest website, staff portal, exclusive appointments, group seats, lifecycle, waitlist, reminders and simulator | Guest/staff browser journeys plus booking, security, retry, expiry and last-seat gates; AI stopped and ordinary booking still works |
| P1 AI pilot | Local inference gateway, intent booking, versioned blueprint builder, trusted page preview, rehearsal and impact review | Actual local-model run separately evidenced; forged approval/invented slot/stale impact rejected; exact guest/owner approval governs mutations |
| P2 growth | Calendar adapter contracts, connectors, controlled recipes, recovery, insights, cells and deployment | Contract/failure/recovery/browser tests; provider activation independently labelled |
| P3 experiments | Flagged same-cell multi-stage prototype, voice/message ports and advice evaluation | Synthetic contract/prototype checks; flags off by default; live voice/provider use not claimed |
| Full handoff | Compose and dedicated kind release, validated cloud templates, restore/rollout evidence and owner pilot script | T41 final-source verification, T42 reviewed handbook and recorded owner acceptance |

## Invariants that define success

1. A persisted booking is the only source of confirmation. At least 100 simultaneous exclusive-slot attempts produce at most one active allocation; more-than-capacity attempts never oversell seats.
2. Tenant A and guest A cannot access tenant B or guest B through APIs, storage, caches, exports, capabilities or AI tools. Staff permissions remain server-enforced.
3. Lost responses, duplicate callbacks and repeated operations do not create duplicate bookings, releases or simulator compensation. An expired hold cannot confirm with its worker stopped. A failed move retains the original reservation.
4. Blueprint publication validates exact current version/hash, resolved material fields, semantic rules, rehearsal and current booking impact. Existing appointments are preserved until separately approved moves succeed.
5. Core booking remains available when inference, calendars or the simulator fail according to the declared integration policy. All inference loops, queues, retries and searches are bounded.
6. Payment behavior is explicitly simulated, with no real financial operations or card fields.
7. Another developer can reproduce the accepted build, local deployment and release checks from the final tested revision and handbook.

## Evidence and exit rule

Every task has a dependency list, allowed scope, acceptance criteria and an evidence record. Local generation produces a review candidate; GPT review plus executed checks allows task acceptance. The full application is complete only when mandatory local gates pass on the final revision, T41/T42 are accepted, and independent readiness labels accurately describe untested external integrations, scale and cloud deployment.

Current task status is recorded in both execution ledgers and the automatic controller state. This goal document and the supporting pack prepare implementation; they do not satisfy T01 or any release gate. Performance targets from the source plans remain targets: availability p95 under 500 ms, mutations p95 under one second for a declared profile, and zero capacity violations. The source scale envelope and recovery objectives require measurements; task count and local GPU size are not delivery or scale evidence.

The owner has authorized all T01–T42 tasks to run sequentially through `scripts/start-development.ps1`, with installed LM Studio models first, GPT implementation failover when needed, independent GPT review, real verification and bounded automatic repair. The controller preserves all acceptance criteria and checkpoints on unresolved prerequisites, finite limits or the original human acceptance gates. See `docs/AUTOMATIC_DEVELOPMENT.md` for the run and recovery contract.

## Development completion for this preparation request

The startup pack is ready when all source plans have been reconciled, T01–T42 have precise packets, architecture/domain/blueprint/verification baselines exist, the ledger reflects actual progress, and startup scripts pass their preparation checks. A capability trial is recorded separately. Java installation, Docker startup and the first application build belong to the following implementation work.
