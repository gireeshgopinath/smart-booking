# Plan analysis and implementation baseline

Analyzed 10 October 2026 (Europe/Berlin). This report describes the starting materials and adopted design decisions. It is not evidence that application features exist.

## Starting state

The initial workspace inventory contained exactly three source artifacts:

| Artifact | Role | Interpretation |
| --- | --- | --- |
| `Booking_Application_Master_Execution_Plan.md` | Version 2.0, 9 October 2026, T01–T42 | Governs complete application scope and task acceptance |
| `Booking_Backend_Local_Agent_Execution_Plan.md` | Version 1.0, 28 September 2026, T01–T26 | Retained detailed backend invariants, API areas, simulator rules and V01–V26 |
| `Booking_Application_Design_and_Development.docx` | Version 2.0, 9 October 2026 | Product design, P0–P3 priorities, UI, builder and review process |

There was no application source tree, Maven wrapper, frontend package, migration, running-service transcript, model run, task ledger or verification evidence in those materials. All implementation tasks start TODO. Existing generated support documents must not be counted as completed application tasks. The DOCX text was inspected directly from its OOXML paragraphs; no source document was changed.

## Findings that affect execution

| Finding | Consequence | Adopted resolution |
| --- | --- | --- |
| Backend v1 excludes frontend, while master v2 and DOCX explicitly add guest/business websites | An agent reading only v1 could deliver the wrong scope | Master v2 governs; retain v1 backend invariants and simulator restrictions |
| Master says the appendix retains the backend contract, but this Markdown file has no appendix | Essential rules are not present in one master file | Read both Markdown plans; the backend file is the retained detailed contract |
| DOCX names an accompanying pack which is absent | Agents cannot follow the referenced specifications as written | Treat new support files as reconstructed baseline documents, not recovered originals |
| T26 says “all prior tasks” and T41 depends on T26 | Interpreting T26 as all 42 tasks would create a dependency cycle | T26 depends on T01–T25 and is the backend checkpoint; T41/T42 complete the whole app |
| T08 requires expiry scheduling; full Temporal workflows arrive at T12 | Literal sequencing could block holds until after T09 | T08 uses durable expiry job records and synchronous deadline checks; T12 adds Temporal dispatch/recovery |
| T12 includes simulated-payment reconciliation before T13 implements the simulator | Potential reverse dependency | T12 defines workflow/Activity contracts and tests business errors; T13 installs the actual simulator operations |
| T22 calls for a live local model, while V16 and T35 allow NOT_RUN if unavailable | Missing model can be misreported as deployment success | Separate functional deployment from `LIVE_LOCAL_MODEL`; missing model never creates fake successful agent responses |
| New A01–A20/R01–R30 are referenced without their definitions | Traceability cannot honestly claim original detailed semantics | Mark reconstructed requirement/gate mappings explicitly; preserve all task prose acceptance criteria |
| Blueprint starter schema/example, architecture/data/AI docs and twelve ADRs are absent | Builder boundaries and publication race behavior are underspecified | Supply a portable starter schema plus precise domain/API/blueprint support; further versions require reviewed migration |
| Rescheduling plus a mandatory independent target hold can conflict with the old booking itself | A move to a partially overlapping interval can become impossible | Reschedule proposal is advisory; approved move atomically swaps allocations, using a scoped deferred exclusion check where needed |
| Impact reports bind affected bookings, but unrelated newly affected bookings may be created afterwards | An old preview can authorize a harmful publication | Include a schedule/inventory guard revision advanced by every relevant mutation; recheck it under the publication locks |
| “Codex local model” and product AI appear together | CLI provider configuration could be mistaken for application model setup | Development agent and application model gateway have separate configuration, identities, budgets and verification |
| Versions, launch market/languages/accounts and cloud budget remain open | Imagined compatible tooling or provider credentials can block later work | T01 records an actual compatibility trial; use synthetic local accounts; keep unconfigured live providers separately labelled |

No dependency cycle is implied by the stated T01–T42 graph after interpreting T26 as T01–T25. Sequence numbers are navigation; dependency readiness controls execution. T27 can start after T02/T09, although T29 remains dependent on T10/T11/T13. The backend checkpoint should not artificially delay dependency-ready frontend work.

## Missing reference inventory

The source materials name `AGENTS.md`, `00_START_HERE.md`, product/architecture/data/AI specifications, `08_MASTER_EXECUTION_PLAN.md`, `09_LOCAL_AI_AND_CHATGPT_GUIDE.md`, `10_VERIFICATION_AND_TRACEABILITY.md`, `contracts/tasks.json`, review templates, a starter blueprint schema, synthetic salon template and twelve ADRs. None was in the initial three-file inventory. New files created for this request are a replacement development pack. Do not attribute their added endpoint shapes or semantic choices to missing original documents.

## Adopted technical baseline

Keep Java 25, stable Spring Boot 4.x, a verified compatible Spring AI release, Maven wrapper, explicit JDBC transactions, PostgreSQL/Flyway/`btree_gist`, Valkey-compatible caching, Keycloak OIDC, Temporal, SQS/LocalStack, Mailpit, React/TypeScript, OpenTelemetry/Micrometer, Compose, kind, Helm, Terraform and the specified test families. Exact patch/image/SDK versions must be pinned by T01 after compatibility checks; this pack does not claim a tested dependency combination.

Implement one modular booking authority per tenant cell, with separate edge, AI runtime, worker and simulator processes. Enforce tenant-aware keys and RLS; both holds and bookings consume the same persistent inventory. Model tools call ordinary authorized domain commands. AI never supplies trusted tenant identity or approves its own mutation. Frontends render validated blueprint data through trusted components.

The first decisive product checkpoint is real tenant isolation plus catalogue → availability → owned hold → exact client approval → idempotent persisted confirmation, with exclusive-resource and last-seat concurrency evidence. AI and UI expansion follow that reliable scheduler. Documentation, healthy containers and generated code do not meet this checkpoint.

## Open decisions and safe defaults

| Decision | Working default | When resolved |
| --- | --- | --- |
| Application repository root | Use current workspace; preserve the three source artifacts; avoid another accidental nested project | T01 inspection |
| Spring Boot/Spring AI/JDK/SDK/image versions | Maintain specified Java/stack; dependency trial and exact manifest required | T01/T02 |
| React/TypeScript framework and rendering | Shared accessible components and generated API client; framework/SSR selection remains an ADR | T27 |
| Actual local model, quantization and provider | Operator-configured endpoint and exact served ID; capability trial before autonomous coding | Development setup and T16 |
| GPU capacity | DOCX's RTX 5080 is prior planning context; discover actual hardware and measure model behavior | Development setup |
| Launch segment/market | Synthetic salon and class demos; no real customers | Before owner pilot |
| Currency/language/time zone | Synthetic EUR and Europe/Berlin examples; do not infer actual business settings from them | T06/T30 and pilot |
| Hold/quote limits and retention | Bounded configurable values, validated and documented per profile | T03/T08/T15 |
| Stale external calendar policy | Per connection `ADVISORY` or `REQUIRED`; required stale source blocks affected new inventory | T14 |
| Production identity, email/calendar accounts and cloud | Dedicated test credentials when provided; no paid deployment from templates | Before activation |
| P3 scope | Default-off experimental contracts, explicitly separate prototype evidence | T39/T41 |

Missing external accounts do not block contract tests or independent local implementation. Missing mandatory local dependencies do block the affected acceptance gate. Runtime failures must be surfaced, not converted into mock success. Final readiness reports distinguish backend, frontend, builder, live model, protocols, local deployments, live providers, cloud and achieved load.

## Support document map

- [System design](architecture/SYSTEM_DESIGN.md): boundaries, repository layout, fault containment and deployment profiles.
- [Domain contract](architecture/DOMAIN_CONTRACT.md): typed entities, invariants, state transitions and transaction algorithms.
- [API baseline](architecture/API_CONTRACT.md): proposed endpoint/operation shapes, errors, auth and retry rules.
- [Blueprint contract](architecture/BLUEPRINT_CONTRACT.md): draft, provenance, rehearsal, impact, owner approval and publication.
- [Starter schema](../contracts/booking-blueprint.schema.json) and [synthetic salon example](../examples/salon.blueprint.json): portable input, not runtime records or authority.
- [Decision records](architecture/adr/README.md): adopted design and unresolved implementation choices.

Use task packets and review evidence with these contracts. Any changed invariant, endpoint or schema must update its support document, generated contracts, applicable tests and affected task packet together.
