# ADR 0003: Model suggestions require exact client approval

Date: 10 October 2026. Status: adopted design baseline; hostile-tool and browser tests pending.

Development Codex local-model use and the finished application's AI runtime are distinct systems. Product models receive bounded typed tools, with actor/tenant/route context bound outside model arguments. They never receive shell, arbitrary SQL, infrastructure administration or approval-creation tools. Untrusted uploads/calendar/description text cannot grant authority.

Guest approvals bind exact server-generated proposal hash/purpose/owner/deadline. Owner blueprint approvals bind exact draft/base version/current impact. Ordinary authenticated client endpoints create them. Tools can consume existing validated approval records; model statements are insufficient. Timeouts trigger operation lookup, and confirmation wording comes from a persisted booking result.

Builder output is schema-validated configuration with provenance, not generated executable page content. Render previews and published pages through the same trusted React component registry. Draft edits invalidate derived approval/impact/rehearsal. Publication rechecks the scheduling guard and affected versions under locks, then updates configuration/outbox/audit atomically. Existing bookings stay intact; rollback creates a newly validated draft.

Consequences: model failure leaves deterministic booking available. Material ambiguity demands clarification rather than inferred publishable defaults. Capability/approval boundary tests are required independently of a live model; live inference integration has its own readiness label.
