# ADR 0004: Simulator and truthful integration evidence

Date: 10 October 2026. Status: adopted design baseline; runtime checks pending.

Payments implement only `DummyPaymentGateway`. Default policy is `NONE`; explicit demo policy can require `SIMULATED_DEPOSIT`. Every event/result/receipt is visibly simulated, scenario choice is operator-only, signed callbacks are durably deduplicated, and late success after release creates simulated compensation rather than taking another booking's inventory. No real provider SDK, card/bank data, credentials or real money call exists.

Provider workflows use at-least-once transport, durable inbox/outbox and idempotent domain actions. SMTP ambiguity may remain unknown; remote calendars cannot commit atomically with local PostgreSQL. External conflicting edits create visible recovery issues without silently deleting bookings. Required-calendar freshness is an explicit policy.

Readiness labels remain independent for backend, frontend/browser, builder, AI contracts, actual live model, protocols, Compose, kind, live provider accounts, cloud templates/deployment, measured load and P3 experiments. Contract fixtures are permitted in tests only; missing services cannot trigger a hidden runtime success provider. P3 flags default off. The design's scale/recovery numbers are targets until measured.

Consequences: unavailable external accounts allow contract implementation but leave live evidence NOT_RUN. Mandatory local gate failures leave the application incomplete. A health check, Terraform validation or laptop dataset count cannot stand in for functional deployment, cloud activation or achieved throughput.
