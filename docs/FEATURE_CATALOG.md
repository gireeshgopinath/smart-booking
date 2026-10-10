# Feature and task catalog

Prepared 10 October 2026. **All application tasks are TODO and all runtime verification is NOT_RUN.** This support pack is ready for development planning; it does not assert an implemented application, running deployment or completed T01.

The [Master execution plan](../Booking_Application_Master_Execution_Plan.md) supplies T01–T42 goals/dependencies and supersedes the [Backend plan](../Booking_Backend_Local_Agent_Execution_Plan.md) backend-only frontend exclusion. Backend §§6–8 retain the domain/security/payment invariants. T26 is the backend checkpoint; T41 and T42 are full application release verification and handoff. Original source files are preserved.

The initial workspace contained the two source plans and a design DOCX only. The Master references architecture/data/AI documents, an included starter schema, `10_VERIFICATION_AND_TRACEABILITY.md` and `contracts/tasks.json` that were absent. The prepared contracts/traceability are derived or proposed artifacts, not recovered original documents. The DOCX analysis is supplied elsewhere in this support pack; packets below cite the source Markdown task sections.

## Use with the local coding model

Read `AGENTS.md`, the ledger, next-step, applicable architecture contracts and one task packet. Select the first dependency-ready incomplete task; T01 is the initial implementation task. For later tasks, dependency PASS requires actual evidence. Keep one bounded slice per session, return exact changed paths/check logs, and request GPT-supported review for contract decisions, security/concurrency changes and unresolved repeated failure. After two repairs of one root cause, return diagnostics instead of expanding scope. Do not ask a local model to implement all 42 tasks in one prompt.

A packet lists planned paths, interfaces, acceptance scenarios, future commands, evidence and escalations. “Planned” never means the files/commands already exist. Packet creation does not satisfy its task. The machine-readable task index is navigation metadata; prose criteria and source plans remain acceptance authority.

Shared contracts:

- [System design](architecture/SYSTEM_DESIGN.md)
- [Domain contract](architecture/DOMAIN_CONTRACT.md)
- [API contract](architecture/API_CONTRACT.md)
- [Blueprint contract](architecture/BLUEPRINT_CONTRACT.md)

## Task index

| Task | Feature/outcome | Exact dependency IDs | Initial state |
| --- | --- | --- | --- |
| [T01](features/T01.md) | Repository assessment and dependency baseline | none | TODO |
| [T02](features/T02.md) | Application skeleton and contracts | T01 | TODO |
| [T03](features/T03.md) | Local dependencies and secret setup | T02 | TODO |
| [T04](features/T04.md) | Tenant directory, OIDC and authorization | T02, T03 | TODO |
| [T05](features/T05.md) | Persistent schema and resource invariants | T04 | TODO |
| [T06](features/T06.md) | Business catalog and scheduling administration | T05 | TODO |
| [T07](features/T07.md) | Availability engine | T06 | TODO |
| [T08](features/T08.md) | Guest sessions, proposals and holds | T04, T05, T07 | TODO |
| [T09](features/T09.md) | Booking confirmation, cancellation and rescheduling | T08 | TODO |
| [T10](features/T10.md) | Capacity sessions and waitlists | T09 | TODO |
| [T11](features/T11.md) | Events, inbox/outbox and notification delivery | T09 | TODO |
| [T12](features/T12.md) | Durable booking workflows | T11 | TODO |
| [T13](features/T13.md) | Dummy payment extension | T09, T11, T12 | TODO |
| [T14](features/T14.md) | Calendar connections and conflict handling | T06, T09, T11 | TODO |
| [T15](features/T15.md) | Reporting, audit access and retention | T09, T10, T11 | TODO |
| [T16](features/T16.md) | Model gateway and AI execution budgets | T02, T04, T11 | TODO |
| [T17](features/T17.md) | Booking agent and mutation authorization | T08, T09, T12, T16 | TODO |
| [T18](features/T18.md) | Business setup, recovery and reporting agents | T15, T17 | TODO |
| [T19](features/T19.md) | MCP and A2A interfaces | T17, T18 | TODO |
| [T20](features/T20.md) | Cell routing and migration safety | T04, T09, T11, T12 | TODO |
| [T21](features/T21.md) | Telemetry, admission and operational controls | T11, T16, T20 | TODO |
| [T22](features/T22.md) | Complete Docker Compose release | T10, T11, T12, T13, T14, T15, T16, T17, T18, T19, T20, T21 | TODO |
| [T23](features/T23.md) | Kubernetes deployment and recovery | T22 | TODO |
| [T24](features/T24.md) | Cloud infrastructure and CI delivery | T22, T23 | TODO |
| [T25](features/T25.md) | Load, resilience and restore verification | T22, T23 | TODO |
| [T26](features/T26.md) | Final independent verification and handoff | T01, T02, T03, T04, T05, T06, T07, T08, T09, T10, T11, T12, T13, T14, T15, T16, T17, T18, T19, T20, T21, T22, T23, T24, T25 | TODO |
| [T27](features/T27.md) | Frontend baseline and shared design system | T02, T09 | TODO |
| [T28](features/T28.md) | Business portal and operational calendar | T06, T09, T10, T15, T27 | TODO |
| [T29](features/T29.md) | Complete guest booking and self management | T08, T09, T10, T11, T13, T27 | TODO |
| [T30](features/T30.md) | Accessibility and localization verification | T28, T29 | TODO |
| [T31](features/T31.md) | Versioned blueprint persistence and semantic validation | T05, T06, T15, T16 | TODO |
| [T32](features/T32.md) | Booking rehearsal and live change impact | T07, T09, T10, T31 | TODO |
| [T33](features/T33.md) | AI builder and conversational customization UI | T18, T28, T31, T32 | TODO |
| [T34](features/T34.md) | Connector registry and declarative mapping | T11, T14, T15, T28 | TODO |
| [T35](features/T35.md) | Intent booking experience and protocol client evidence | T17, T19, T29, T30 | TODO |
| [T36](features/T36.md) | Portable templates and safe automation recipes | T31, T33, T34 | TODO |
| [T37](features/T37.md) | Disruption and cancellation recovery workflow | T10, T12, T18, T28, T29, T34 | TODO |
| [T38](features/T38.md) | Explainable business insights and product measurements | T15, T18, T28, T33 | TODO |
| [T39](features/T39.md) | Future feature experimental contracts | T31, T35, T37, T38 | TODO |
| [T40](features/T40.md) | Whole application deployment and capacity measurement | T23, T24, T25, T30, T33, T34, T35, T36, T37, T38 | TODO |
| [T41](features/T41.md) | Independent full application release verification | T26, T30, T33, T35, T36, T37, T38, T39, T40 | TODO |
| [T42](features/T42.md) | Handoff and pilot readiness decision | T41 | TODO |

T22 source range T10–T21 is inclusive. T26 “all prior tasks” is T01–T25. Other dependencies are retained exactly from Master. Backend tasks lack explicit R labels in their task prose; do not fabricate source requirement assignments. T27–T42 retain their given R IDs for future reconciliation. Original R definitions were not supplied; the verification matrix uses separately labelled B baseline requirements.

The proposed release verifier has explicit scope: `make verify-release SCOPE=backend` runs retained V gates for T26, while `make verify-release SCOPE=application` runs V and A gates for T41. Neither scope claims the final H01 handbook/pilot/owner acceptance, which belongs to T42. Implement the scope mapping before using these future commands; whole-project readiness remains incomplete until the final handoff.

## Preparation decisions and implementation boundaries

These are proposed resolutions to record/review in T01 and relevant ADRs, not claims that a build choice has been validated:

| ID | Decision | Why/when to validate |
| --- | --- | --- |
| PD01 | Workspace root is the repository root; no nested booking-platform folder. | Avoids duplicate source/support pack. Ratify T01. |
| PD02 | Verify Java 25 / stable Spring Boot 4.x / compatible Spring AI candidate before exact pins. | Backend §4.2 names this baseline; actual compatibility/build evidence is required. |
| PD03 | Reconstruct missing referenced contracts/schema/gates with explicit provenance. | Needed for precise implementation; do not present inferred R/A text as supplied original. |
| PD04 | Provide exact make targets or documented cross-platform wrapper mapping. | Windows/WSL setup must propagate exit/status and guard target environment. |
| PD05 | Local model implements bounded slices; GPT-supported Codex review evaluates evidence and guides next slice. | Development orchestration is separate from runtime AI tools and client-only approval. |

No real payment gateway is in scope. Free anonymous booking must work when OIDC, model and simulator are unavailable. Tenant authorization, real PostgreSQL resource constraints, durable idempotency and exact client-created approval are mandatory. Reschedule proposals are advisory; approved commit swaps allocations atomically and preserves the old booking on conflict. Tenant scheduling guards advance for inventory/configuration/external-busy changes and invalidate stale impact preview.

Local model/protocol/calendar/cloud/scale readiness is recorded independently. Deterministic model/provider fixtures prove contracts only; live results need actual endpoint/account evidence. P3 experiments in T39 default off. A mandatory failed/blocked local gate prevents full release completion. The retained and additional final gates are future verification requirements, not executed checks.

