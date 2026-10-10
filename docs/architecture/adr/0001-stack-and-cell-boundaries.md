# ADR 0001: Retain stack and cell transaction boundary

Date: 10 October 2026. Status: adopted design baseline; dependency trial pending.

The master and design specify Java 25, stable Spring Boot 4.x, compatible Spring AI, Maven, JDBC, PostgreSQL, Valkey, OIDC/Keycloak, SQS/LocalStack, Temporal, SMTP inbox, React/TypeScript and local/cloud deployment tooling. Preserve these. T01 pins actual compatible patch/image/SDK versions after a real build trial. Do not replace the stack because a coding model prefers another framework.

Catalogue, scheduling, proposals, allocations, capacity and blueprint publication live in one booking deployable/database per cell. Edge, AI runtime, workers and simulator are separate deployables for resource/failure containment. A module can host the tool gateway; a service per domain noun adds distributed consistency without a requirement.

One tenant has one writable cell, controlled by directory epoch plus cell-local fence. Multi-resource reservations stay inside that tenant/cell. Two-cell testing proves the specified failure envelope while disclosing shared physical/identity/workflow/directory dependencies.

Consequences: short local transactions enforce inventory; optional AI failures are isolated. Initial tenant-wide scheduling guard limits hot-tenant parallelism and must be measured. A framework or finer-grained locking change needs recorded compatibility/concurrency evidence. React framework and public SSR/SEO decision remain open for T27, not guessed here.
