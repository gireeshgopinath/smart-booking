# Application task ledger

Controller update: 2026-10-10T17:36:44.7502213Z. 0 / 42 tasks accepted. Current task T01 is IN_PROGRESS, attempt 3, review PENDING. task-ledger.json is authoritative; this table is synchronized in the same journaled transaction. Preparation, code generation and mocks do not establish application acceptance.

| Task | Goal | Dependencies | Status | Attempts | Review | Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| T01 | Repository assessment and dependency baseline | none | IN_PROGRESS | 3 | PENDING | docs/verification/T01/session-001/supervisor-preflight.json |
| T02 | Application skeleton and contracts | T01 | TODO | 0 | PENDING | none |
| T03 | Local dependencies and secret setup | T02 | TODO | 0 | PENDING | none |
| T04 | Tenant directory, OIDC and authorization | T02, T03 | TODO | 0 | PENDING | none |
| T05 | Persistent schema and resource invariants | T04 | TODO | 0 | PENDING | none |
| T06 | Business catalog and scheduling administration | T05 | TODO | 0 | PENDING | none |
| T07 | Availability engine | T06 | TODO | 0 | PENDING | none |
| T08 | Guest sessions, proposals and holds | T04, T05, T07 | TODO | 0 | PENDING | none |
| T09 | Booking confirmation, cancellation and rescheduling | T08 | TODO | 0 | PENDING | none |
| T10 | Capacity sessions and waitlists | T09 | TODO | 0 | PENDING | none |
| T11 | Events, inbox/outbox and notification delivery | T09 | TODO | 0 | PENDING | none |
| T12 | Durable booking workflows | T11 | TODO | 0 | PENDING | none |
| T13 | Dummy payment extension | T09, T11, T12 | TODO | 0 | PENDING | none |
| T14 | Calendar connections and conflict handling | T06, T09, T11 | TODO | 0 | PENDING | none |
| T15 | Reporting, audit access and retention | T09, T10, T11 | TODO | 0 | PENDING | none |
| T16 | Model gateway and AI execution budgets | T02, T04, T11 | TODO | 0 | PENDING | none |
| T17 | Booking agent and mutation authorization | T08, T09, T12, T16 | TODO | 0 | PENDING | none |
| T18 | Business setup, recovery and reporting agents | T15, T17 | TODO | 0 | PENDING | none |
| T19 | MCP and A2A interfaces | T17, T18 | TODO | 0 | PENDING | none |
| T20 | Cell routing and migration safety | T04, T09, T11, T12 | TODO | 0 | PENDING | none |
| T21 | Telemetry, admission and operational controls | T11, T16, T20 | TODO | 0 | PENDING | none |
| T22 | Complete Docker Compose release | T10, T11, T12, T13, T14, T15, T16, T17, T18, T19, T20, T21 | TODO | 0 | PENDING | none |
| T23 | Kubernetes deployment and recovery | T22 | TODO | 0 | PENDING | none |
| T24 | Cloud infrastructure and CI delivery | T22, T23 | TODO | 0 | PENDING | none |
| T25 | Load, resilience and restore verification | T22, T23 | TODO | 0 | PENDING | none |
| T26 | Final independent verification and handoff | T01, T02, T03, T04, T05, T06, T07, T08, T09, T10, T11, T12, T13, T14, T15, T16, T17, T18, T19, T20, T21, T22, T23, T24, T25 | TODO | 0 | PENDING | none |
| T27 | Frontend baseline and shared design system | T02, T09 | TODO | 0 | PENDING | none |
| T28 | Business portal and operational calendar | T06, T09, T10, T15, T27 | TODO | 0 | PENDING | none |
| T29 | Complete guest booking and self management | T08, T09, T10, T11, T13, T27 | TODO | 0 | PENDING | none |
| T30 | Accessibility and localization verification | T28, T29 | TODO | 0 | PENDING | none |
| T31 | Versioned blueprint persistence and semantic validation | T05, T06, T15, T16 | TODO | 0 | PENDING | none |
| T32 | Booking rehearsal and live change impact | T07, T09, T10, T31 | TODO | 0 | PENDING | none |
| T33 | AI builder and conversational customization UI | T18, T28, T31, T32 | TODO | 0 | PENDING | none |
| T34 | Connector registry and declarative mapping | T11, T14, T15, T28 | TODO | 0 | PENDING | none |
| T35 | Intent booking experience and protocol client evidence | T17, T19, T29, T30 | TODO | 0 | PENDING | none |
| T36 | Portable templates and safe automation recipes | T31, T33, T34 | TODO | 0 | PENDING | none |
| T37 | Disruption and cancellation recovery workflow | T10, T12, T18, T28, T29, T34 | TODO | 0 | PENDING | none |
| T38 | Explainable business insights and product measurements | T15, T18, T28, T33 | TODO | 0 | PENDING | none |
| T39 | Future feature experimental contracts | T31, T35, T37, T38 | TODO | 0 | PENDING | none |
| T40 | Whole application deployment and capacity measurement | T23, T24, T25, T30, T33, T34, T35, T36, T37, T38 | TODO | 0 | PENDING | none |
| T41 | Independent full application release verification | T26, T30, T33, T35, T36, T37, T38, T39, T40 | TODO | 0 | PENDING | none |
| T42 | Handoff and pilot readiness decision | T41 | TODO | 0 | PENDING | none |

Only T01 is dependency-ready. Prepared T01-S01 remains gated on local model admission and exclusive writer availability; prerequisites and scope are in next-step.md. T26 depends on T01-T25. T42 requires final owner pilot acceptance; a supervisor may review evidence but cannot invent owner acceptance.

Task states: TODO, IN_PROGRESS, PASS, FAIL, BLOCKED. Review states: PENDING, APPROVED, CHANGES_REQUIRED. Checks may additionally be NOT_RUN where external validation is unavailable; NOT_RUN is not a task PASS.
