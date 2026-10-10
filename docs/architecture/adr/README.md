# Architecture decision index

These are adopted design recommendations for the development pack. They describe decisions to implement; none asserts proven runtime behavior. T01/T02 record actual dependency compatibility and generated contracts. T27 records the frontend framework/rendering decision. Record alternatives and evidence whenever implementation changes a decision below.

| ADR | Decision | Verification owner |
| --- | --- | --- |
| [0001](0001-stack-and-cell-boundaries.md) | Retain specified stack, modular booking authority and separate fault/resource boundaries | T01/T02/T20 |
| [0002](0002-reservation-authority.md) | PostgreSQL inventory, tenant guard, RLS, idempotency, atomic move and deferred overlap validation | T05/T08/T09/T10/T32 |
| [0003](0003-ai-approval-and-blueprints.md) | Typed model tools, client-created exact approval, data-only blueprint publication and trusted renderer | T17/T18/T31–T36 |
| [0004](0004-provider-and-evidence-boundaries.md) | Simulator-only payment, provider ambiguity, independently labelled readiness and scope | T13/T14/T22–T26/T39–T42 |

The original DOCX mentions twelve detailed decision records that were not present. This replacement index intentionally does not pretend to recover their numbers/content. Create additional ADRs when the actual implementation makes further decisions.
