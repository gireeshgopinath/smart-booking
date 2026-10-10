# Complete application execution plan

Version 2.0 | 9 October 2026

## Execution goal

Deliver a working guest website, authenticated business portal, multi-tenant booking backend, safe AI builder/assistants, local deployments and evidence-backed handoff. The default guest flow requires no registration, AI or payment service. Payments are simulator-only.

This plan retains the original T01–T26 task definitions and adds T27–T42. The earlier backend-only exclusion is superseded for this application. T26 remains a backend checkpoint, not the full application completion gate. The architecture/data/AI documents add blueprint and UI requirements; the appendix remains the detailed retained backend contract.

## Task execution contract

Execute one dependency-ready task per bounded session. Read AGENTS.md, the ledger and relevant specifications. Inspect git status and actual tools. Implement behavior, run meaningful checks, fix bounded failures and record actual evidence. Do not claim PASS from code generation alone. Use TODO, IN_PROGRESS, PASS, FAIL or BLOCKED. After two repair attempts at the same root cause, produce a diagnostic packet for ChatGPT.

Every task records goal, dependencies, changed paths, commands/exit codes, timestamp, revision, evidence and limitations. Use review templates. Establish operator entry points during T01–T03 and expand them as their behavior is implemented; commands listed below are requirements for the future repository, not commands already provided by this design pack.

## Recommended milestones

M1 T01–T05 establishes build, identities and enforced database invariants. M2 T06–T13 completes core booking and simulator. M3 T14–T19 adds adapters and controlled agents. M4 T20–T26 verifies cells, deployment and backend. Frontend tasks T27–T30 can start when their backend dependencies are ready. M5 T31–T36 delivers the intelligent builder and connected intent booking. M6 T37–T40 adds recovery, insights, experimental contracts and deployment. T41–T42 verifies and hands off the whole application.

Do not estimate delivery from task count alone. Estimate after M1 and the first complete booking slice using actual local-model iteration time. Security/concurrency tasks need explicit review; small UI changes need appropriate visual checks.

## Retained backend tasks

### T01 — Repository assessment and dependency baseline

**Depends on:** none.  
**Goal:** establish the actual starting state and a reproducible build.

Inspect existing code and repository instructions, identify reusable parts and risks, create the execution ledger, and pin compatible toolchain/dependency versions. Record decisions and scope boundaries, including no real payments. Create Maven wrapper, shared formatting, compiler and test configuration.

**Verify:** clean wrapper build works; dependency resolution and tool versions are recorded; no unrelated files were overwritten.  
**Evidence:** `docs/execution/repository-assessment.md`, dependency/version manifest, build log.

### T02 — Application skeleton and contracts

**Depends on:** T01.  
**Goal:** runnable applications with explicit boundaries and real health checks.

Create deployables/modules, typed domain identifiers, injected clocks, configuration validation, error format, request correlation, OpenAPI generation, and version information. Establish environment profiles. Keep liveness independent of optional integrations; readiness reflects required dependencies.

**Verify:** each application starts with valid configuration and fails clearly for invalid configuration; documented API schemas match runtime routes.  
**Evidence:** startup tests, OpenAPI artifact, ADR describing boundaries.

### T03 — Local dependencies and secret setup

**Depends on:** T02.  
**Goal:** start a complete reproducible local environment.

Create Compose services for PostgreSQL, cache, Keycloak, Temporal with persistent backing storage, LocalStack SQS, and local SMTP inbox. Separate application and workflow database roles/databases. Generate local secrets into ignored files; provide `.env.example` without real credentials. Implement `make doctor`, `make deps-up`, and readiness-aware startup.

**Verify:** a fresh named project starts; dependencies are reachable; restart preserves expected data; external ports bind to loopback by default.  
**Evidence:** dependency health report and startup command transcript.

### T04 — Tenant directory, OIDC and authorization

**Depends on:** T02, T03.  
**Goal:** authenticate business users and isolate tenant access.

Implement tenant onboarding, membership and roles `OWNER`, `MANAGER`, `STAFF`, and restricted platform operator. Import local OIDC realm and test identities. Provision tenant-to-cell assignments; cache routes with a generation/epoch. Add least-privilege service identities and internal endpoint authentication.

**Verify:** bad issuer/audience/expiry/signature is rejected; tenant A staff cannot access tenant B; guessed IDs and tenant headers cannot bypass membership; staff cannot grant themselves owner rights.  
**Evidence:** real OIDC integration tests and authorization matrix.

### T05 — Persistent schema and resource invariants

**Depends on:** T04.  
**Goal:** enforce the domain contract in PostgreSQL.

Write Flyway migrations, role grants, tenant-aware foreign keys, row-level security, allocation exclusion constraints, indexes, state checks, idempotency uniqueness, and outbox/inbox schemas. Introduce explicit transaction boundaries and repository interfaces. Keep active exclusive allocations in a constraint-safe layout.

**Verify:** fresh migration and upgrade from the previous migration fixture pass; direct SQL attempts violate the expected constraint; pooled tenant context is reset; runtime roles cannot bypass RLS. Use PostgreSQL Testcontainers, not H2.  
**Evidence:** database invariant tests and migration logs.

### T06 — Business catalog and scheduling administration

**Depends on:** T05.  
**Goal:** businesses can configure their actual bookable inventory.

Implement locations, service publication, durations/buffers, prices/currencies, resources and requirements, staff assignments, recurring working hours, leave/holiday exceptions, booking policies, advance windows and schedule revisions. Track audit events and soft-delete rules for referenced entities.

**Verify:** invalid intervals, unsupported currencies, negative prices, unauthorized staff/resource relationships and incompatible configuration updates are rejected; archived services disappear from public discovery while historical bookings remain readable.  
**Evidence:** API integration tests and sample request collection.

### T07 — Availability engine

**Depends on:** T06.  
**Goal:** generate correct candidate appointments efficiently.

Intersect working hours, resource requirements, exceptions, buffers, capacity, advance limits and active allocations. Bound search windows and result counts. Implement cache keys including tenant and relevant schedule versions, event-based invalidation, short TTL and request coalescing. External busy periods will be added by T14.

**Verify:** DST gaps/overlaps, overnight schedules, adjacent intervals, multiple resources, service buffers, leave, different zones and stale cache behavior. Compare representative generated results with a simple deterministic reference algorithm.  
**Evidence:** availability test matrix and initial latency measurements.

### T08 — Guest sessions, proposals and holds

**Depends on:** T04, T05, T07.  
**Goal:** a customer can safely reserve a choice without account registration.

Implement guest capabilities, contact details minimization, immutable proposals, quote expiry, exact approval records, resource holds, expiry scheduling and opportunistic expired-hold cleanup. Enforce quotas per tenant and guest, with additional abuse controls. Enforce held proposal ownership and schedule revisions.

**Verify:** anonymous end-to-end hold succeeds without OIDC; another guest cannot read or mutate it; changed price or terms invalidates approval; delayed expiry worker cannot allow expired confirmation.  
**Evidence:** guest-flow tests, token redaction tests, quota tests.

### T09 — Booking confirmation, cancellation and rescheduling

**Depends on:** T08.  
**Goal:** deliver the complete free-booking lifecycle.

Implement approved hold confirmation, durable idempotent results, operation lookup, management token exchange/recovery, cancellation policy enforcement, atomic rescheduling, staff booking/check-in/completion/no-show transitions, and audit history. Confirmed rows and resource allocations must commit together.

**Verify:** simultaneous booking attempts cannot overlap; lost HTTP response plus retry yields one booking; failed reschedule retains the old allocation; repeated cancel releases capacity once.  
**Evidence:** lifecycle integration tests and concurrent allocation results.

### T10 — Capacity sessions and waitlists

**Depends on:** T09.  
**Goal:** handle limited group places and fill released appointments.

Implement fixed-capacity occurrences, atomic hold/place accounting, guest waitlist entry, policy-based offer selection, expiring offer capabilities and acceptance. A waitlist offer reserves according to an explicit short-lived policy; accepting it goes through normal approval and booking rules. Prevent multiple active offers from overselling the same inventory.

**Verify:** capacity N with concurrent N+ requests never exceeds N; duplicate release is harmless; expired offers cannot book; cancellation can lead to one valid new offer.  
**Evidence:** capacity and waitlist concurrency tests.

### T11 — Events, inbox/outbox and notification delivery

**Depends on:** T09.  
**Goal:** durable side effects without losing or duplicating business state.

Implement outbox relay leases, SQS publishing, consumer inbox deduplication, retry/backoff, dead letter handling and replay tooling. Dispatch email into the local inbox, provide SMTP adapter configuration and an SMS development sink. Record reminder jobs, cancellation suppression, time zones and delivery status. Use transactional job creation or idempotent workflow-start records so accepted bookings cannot lose reminders.

**Verify:** stop relay between commit and publish, restart it, and observe eventual delivery; duplicate event delivery causes no duplicate business transition; cancellation suppresses a pending reminder. Define provider-send ambiguity honestly, since an SMTP timeout may leave delivery uncertain.  
**Evidence:** queue fault tests, inbox messages, dead letter replay demonstration.

### T12 — Durable booking workflows

**Depends on:** T11.  
**Goal:** resume long processes safely after worker restarts.

Implement Temporal workflows for hold expiry, reminder scheduling, simulated payment reconciliation, and compensation. Use stable workflow IDs, deterministic workflows, bounded retries and explicit business errors. Run database/network/model calls through Activities. Version workflow changes and document upgrade safety. Workflows call authorized booking APIs/domain operations rather than bypassing constraints.

**Verify:** terminate a worker during an active workflow, restart it, and observe one legal final state; replay tests detect non-deterministic changes; business rejections do not retry forever.  
**Evidence:** workflow history identifiers and restart/replay tests.

### T13 — Dummy payment extension

**Depends on:** T09, T11, T12.  
**Goal:** demonstrate a future payment integration without real payments.

Implement every requirement in section 8. Include a standalone simulator, protected scenario selection, signed callbacks, durable inbox, reconciliation and simulated refund recovery. Provide a demo tenant and scripted walkthrough. Keep ordinary booking independent of simulator health.

**Verify:** all listed scenarios work; bad signatures are rejected; late success cannot take a reallocated slot; retries do not create duplicate simulated intents or refunds; no payment provider dependency, credential field, or outgoing provider call exists.  
**Evidence:** simulator matrix, local walkthrough and dependency/egress checks.

### T14 — Calendar connections and conflict handling

**Depends on:** T06, T09, T11.  
**Goal:** connect external calendars through replaceable adapters.

Implement Google and Microsoft OAuth flows with state/PKCE where applicable, least-required scopes, encrypted token storage, refresh handling, cursor-based incremental synchronization where supported, webhook validation, subscription renewal, bounded polling fallback and disconnect/revocation. Model imported busy periods and provenance. Export confirmed bookings idempotently and suppress feedback loops. Never import external content as model instructions.

**Verify:** contract tests cover duplicate notifications, expired cursor requiring resync, revoked tokens, provider throttling and a conflicting external edit. A conflict after local confirmation creates a visible resolution case; do not silently delete the guest's booking.  
**Evidence:** provider contract tests; live test IDs only if dedicated credentials are available, otherwise label live tests NOT_RUN.

### T15 — Reporting, audit access and retention

**Depends on:** T09, T10, T11.  
**Goal:** provide business insight and controlled data lifecycle.

Implement bounded utilization, completed booking, cancellation and no-show reports; separate simulated financial values. Add audit filtering, asynchronous exports, retention jobs and customer data export/erasure handling with documented audit retention rules. Protect exports with scoped expiring access. Do not use uncontrolled model-generated SQL.

**Verify:** report totals match seeded transactions; tenant-crossing exports fail; retention does not remove active allocations; secrets and sensitive content are absent from logs and audit payloads.  
**Evidence:** reporting reconciliation and retention tests.

### T16 — Model gateway and AI execution budgets

**Depends on:** T02, T04, T11.  
**Goal:** run models independently of booking capacity.

Implement configurable model adapters with a local OpenAI-compatible endpoint option. Configure base URL, actual served model ID, credentials reference, connection limits, token limits, deadline and per-tenant budgets. Discover or verify model availability without assuming a particular name. Implement bounded retries, circuit breaking, per-provider admission and cancellation. Expose streaming run status via SSE. Provide an explicit deterministic provider for tests only; never silently substitute it when a real endpoint fails.

**Verify:** unavailable model produces a clear agent failure while normal booking works; quota exhaustion returns a bounded response; oversized context and excessive tool loops stop; SSE reconnection recovers run status.  
**Evidence:** model adapter contract tests and configured-provider diagnostics without secrets.

### T17 — Booking agent and mutation authorization

**Depends on:** T08, T09, T12, T16.  
**Goal:** book through natural language with the same backend guarantees.

Implement tools for catalog lookup, availability search, proposal preparation, scoped hold creation, approved confirmation and operation status. Generate schemas from typed contracts. Tool authorization independently validates actor, tenant, capability, operation limits and approval. Agent checkpoints include run ID, model/prompt/tool versions and operation IDs. Bind tenant context outside model control. Keep customer contacts out of prompts unless strictly necessary.

Support requests such as “Any staff member Friday after four,” but require clarification for ambiguity about date, zone, location, or service. Present exact verified terms and wait for a client-created approval. After an uncertain mutation result, query operation status. Report confirmation only from a persisted booking response.

**Verify:** forged model approval, foreign tenant IDs, stale quotes, invented slots, indirect prompt injection in service descriptions, double tool calls and request timeouts cannot bypass invariants.  
**Evidence:** agent trace/evaluation results and a live local-model booking run when available.

### T18 — Business setup, recovery and reporting agents

**Depends on:** T15, T17.  
**Goal:** provide useful narrow agent roles with enforceable permissions.

Setup agent drafts service/schedule changes; authorized staff approve versioned diffs before application. Recovery agent reads persisted issues and proposes cancellation/rescheduling or simulator compensation under existing policies. Reporting agent calls prebuilt authorized aggregate tools. Dispatch only the needed role for a request; cap handoffs and tool calls. Store draft provenance and approval records.

**Verify:** setup cannot grant roles or edit schedules without approval; reporting cannot retrieve another tenant; recovery cannot refund real money or repeat a completed operation; stale setup drafts fail safely.  
**Evidence:** role-specific evaluation suites and approved-diff demonstration.

### T19 — MCP and A2A interfaces

**Depends on:** T17, T18.  
**Goal:** expose real interoperable agent interfaces over existing contracts.

Pin published supported protocol versions. Implement MCP tool discovery/calls and A2A Agent Card/task behavior using current official specifications, authentication and audience validation. A2A tasks may enter an input-required state while waiting for approval; task completion must map to an actual recorded result. Declare only implemented capabilities. Restrict externally exposed tools and pass structured authorized context into the same tool gateway. Document current SDK compatibility rather than inventing protocol behavior.

**Verify:** run an independent standards-compatible client against each endpoint; verify discovery, tool/task invocation, input-required state, cancellation, invalid audience rejection, unauthorized mutation rejection and successful approved booking. Handcrafted JSON returning HTTP 200 alone is insufficient evidence of interoperability.  
**Evidence:** client versions, protocol test output and supported-capability document.

### T20 — Cell routing and migration safety

**Depends on:** T04, T09, T11, T12.  
**Goal:** prove isolation and safe scaling beyond one database.

Add a two-cell Compose profile with independent booking databases, caches/queues where relevant, and routable application instances. Map whole tenants to a cell. Implement route epochs and cell-local writer fencing checked on every mutation. Add a controlled migration tool that freezes source writes, drains in-flight transactions, copies consistent tenant data, verifies counts/checksums, switches routing, activates the destination, and rejects stale source writers. Include idempotency state, guest capabilities, approvals, pending jobs and workflow routing. A brief planned tenant pause is acceptable and must be documented.

**Verify:** tenant A and B route to different cells; stopping one cell leaves the other usable; migration under generated traffic results in one active writer and no overlapping allocation; delayed source events cannot mutate a stale cell.  
**Evidence:** isolation test, migration transcript and reconciliation report.

### T21 — Telemetry, admission and operational controls

**Depends on:** T11, T16, T20.  
**Goal:** make overload and failure observable and bounded.

Implement traces from request through database/outbox/worker/agent tools; counters and histograms for conflicts, hold expiry, queue age, notification status, workflow retries, provider latency and token usage. Use low-cardinality metric labels; do not put customer IDs or arbitrary tenant IDs on global metric series. Add per-tenant quotas, pool limits, request deadlines, backpressure and circuit breakers. Provide dashboards and alerts with a runbook for each.

**Verify:** generated failures appear in metrics and traces without secrets; excessive tenant A traffic does not starve B within the recorded test envelope; dependency outages do not cause an unlimited retry storm.  
**Evidence:** dashboard definitions, alert tests and resource-bound measurements.

### T22 — Complete Docker Compose release

**Depends on:** T10–T21.  
**Goal:** a new developer can run and demonstrate the complete backend.

Create production-style non-root application images, reproducible builds, persistent volumes, health checks and project-scoped networking. Create `make up`, `make seed`, `make smoke`, `make e2e`, `make down` and an explicit guarded reset command. Default seeds create two synthetic businesses, role-specific users, services, schedules and a demo simulator scenario. No seed should run automatically in production.

**Verify:** run from a clean project-scoped environment; execute the full HTTP journey, inspect a delivered local email, run AI against the configured local model, and repeat after application restart. Run the two-cell profile separately.  
**Evidence:** reproducibility transcript, image identifiers and health plus functional verification report.

### T23 — Kubernetes deployment and recovery

**Depends on:** T22.  
**Goal:** deploy the same application images to a dedicated local cluster.

Create Helm chart, local and production values, resource requests/limits, startup/readiness/liveness probes, disruption budgets, graceful termination, restricted security contexts, network policies, service accounts, separate worker deployments, HPA/KEDA templates, and a controlled migration Job. Default local ingress/port-forwarding remains local. Production values reference external secrets and managed dependencies; they do not deploy known development credentials. Pin any required ingress, autoscaling and monitoring dependencies and document installation.

Use a dedicated `booking-dev` kind cluster and namespace. If multiple nodes are necessary for the failure drill, configure them explicitly. Install a network policy-capable CNI when verifying policy enforcement; applying NetworkPolicy YAML to an unsupported network is not a passed isolation test.

**Verify:** Helm lint and render, server-side validation, rollout readiness, actual backend smoke journey through ingress, pod termination during a workflow, API rolling upgrade, backward-compatible migration behavior and release rollback. Demonstrate configuration/secrets readiness and observability access. Helm rollback does not undo database migrations; document expand/contract migrations and recovery limits.  
**Evidence:** rendered manifests, release/image versions, rollout, recovery and functional test logs.

### T24 — Cloud infrastructure and CI delivery

**Depends on:** T22, T23.  
**Goal:** prepare a reviewable deployment path beyond the laptop.

Create Terraform modules/examples for AWS network, managed Kubernetes, private PostgreSQL, cache, SQS/dead letter queues, registry, secrets references, workload identities, logs, TLS/ingress and backup configuration. Include one-cell and additional-cell inputs and managed OIDC/Temporal connection settings. Validate provider/region availability at deployment time. Avoid one database per end user. Provide cost-driving variables and teardown/runbook safeguards.

CI must compile, test against PostgreSQL, scan dependencies and images, generate an SBOM, build immutable images, validate charts/Terraform, and archive test evidence. Separate the cloud plan from apply. Use workload identity/OIDC where possible rather than long-lived cloud keys. Prepare Argo CD application definitions for an existing authorized cluster; do not silently install a new control plane into another environment.

**Verify:** formatting, Terraform init without backend when appropriate, validate, chart checks, and CI workflow validation. An actual cloud plan/apply needs credentials and a specified environment; report separately when unavailable.  
**Evidence:** infrastructure validation, CI definition/results, deployment runbook and explicit cloud status.

### T25 — Load, resilience and restore verification

**Depends on:** T22, T23.  
**Goal:** measure capacity and prove recovery under realistic failures.

Create deterministic synthetic datasets and k6 scenarios for catalog reads, availability, holds, confirmation, management, hot resources, capacity sessions, staff mutations and agent runs. Include skewed tenant traffic and both warm/cold caches. Use a dedicated disposable test environment. Provide `local-smoke`, `local-stress`, and `scale-target` profiles with explicit rates/durations; never launch a heavy profile automatically against an arbitrary endpoint.

Run local functional concurrency and a measured bounded load test. Preserve environment specs, replica counts, database/pool settings, generator limits, achieved throughput, p50/p95/p99, error classifications, CPU/memory, queue age and model quotas. Separate expected inventory conflicts from server errors. Run a database backup/restore drill into an isolated database and compare resource invariants, pending operations and data counts. Test cache outage, queue delivery duplication, worker termination, model outage and a stale route during migration.

**Verify:** mandatory local results meet the chosen profile's documented thresholds; one failed dependency cannot invent a confirmation; restore recovers a consistent dataset and documents treatment of in-flight provider events.  
**Evidence:** raw load output, charts or summaries, environment manifest and restore/resilience logs. Larger target numbers remain unverified unless actually achieved.

### T26 — Final independent verification and handoff

**Depends on:** all prior tasks.  
**Goal:** demonstrate completion from the final source state.

Perform a fresh final verification using public/backend interfaces, distinct tenants/guests, and actual running services. Re-run affected gates after any fixes. Check that documented commands match executable scripts and that example payloads match OpenAPI. Confirm no unfinished core path, default-success placeholder, development identity bypass, real gateway integration or hidden simulator fallback remains.

Produce `docs/verification/final-report.md`, updated task ledger, API examples, architecture diagrams, deployment/restore runbooks and `docs/execution/next-step.md`. Report status labels from section 2, exact verified revision/images, evidence, remaining external prerequisites, known limitations, and concrete next actions. Do not declare “production ready” or “supports a million concurrent users” from a laptop test.

**Verify:** every PASS links to reproducible evidence and every exclusion/NOT_RUN is visible; the default guest booking path completes without OIDC, AI or simulator availability.  
**Evidence:** final report and machine-readable summary with gate IDs and exit codes.


## Additional whole application tasks

### T27 Frontend baseline and shared design system

**Depends on:** T02, T09.  
**Requirement IDs:** R02,R08.  
**Target paths:** apps/guest-web, apps/business-web, shared UI and frontend lockfile.  
**Goal and implementation:** Select and pin the React/TypeScript framework and Node toolchain. Create accessible shared components, generated typed API client, session/CSRF handling, routing and error states. Decide public rendering/SEO behavior in ADR. Create lint, typecheck, unit and browser-test commands.

**Acceptance:** Both apps render; invalid API responses surface errors; no private data enters public bundles; typecheck/lint pass.

**Required entry points:** `make frontend-check; make ui-test`. Implement the commands by the relevant task before claiming these checks passed. Include meaningful unit/integration/browser tests appropriate to the behavior; preserve actual logs in `docs/verification/T27/` and a review packet in `docs/execution/review-packets/T27.md`.

### T28 Business portal and operational calendar

**Depends on:** T06, T09, T10, T15, T27.  
**Requirement IDs:** R03,R04,R08,R09,R12.  
**Target paths:** apps/business-web and business API client.  
**Goal and implementation:** Implement OIDC login, scoped location selector, day/week/list calendars, manual booking, staff/resource/service editing, scheduling exceptions, attendance, pending approval and audit view. Use API version checks; drag/move opens a proposal review.

**Acceptance:** Owner and restricted staff flows pass browser tests; direct forbidden API call fails; reschedule conflict preserves original booking.

**Required entry points:** `make frontend-check; make business-e2e`. Implement the commands by the relevant task before claiming these checks passed. Include meaningful unit/integration/browser tests appropriate to the behavior; preserve actual logs in `docs/verification/T28/` and a review packet in `docs/execution/review-packets/T28.md`.

### T29 Complete guest booking and self management

**Depends on:** T08, T09, T10, T11, T13, T27.  
**Requirement IDs:** R01,R02,R05,R06,R07,R10,R11,R13.  
**Target paths:** apps/guest-web and guest-session client.  
**Goal and implementation:** Implement catalogue, date/list availability, party size, contact form, hold/review/approval/confirmation, operation lookup, management-token fragment exchange, cancel/reschedule/recovery and waitlist. Simulator UI is demo-only and visibly labelled.

**Acceptance:** Fresh anonymous browser books and receives local email; retry does not duplicate; stale slot preserves inputs; guest cannot manage another guest booking; default free booking works with model/simulator disabled.

**Required entry points:** `make guest-e2e; make simulator-test`. Implement the commands by the relevant task before claiming these checks passed. Include meaningful unit/integration/browser tests appropriate to the behavior; preserve actual logs in `docs/verification/T29/` and a review packet in `docs/execution/review-packets/T29.md`.

### T30 Accessibility and localization verification

**Depends on:** T28, T29.  
**Requirement IDs:** R02,R14.  
**Target paths:** frontend accessibility tests and translation bundles.  
**Goal and implementation:** Implement labelled fields, focus/focus return, keyboard calendar alternatives, accessible errors, screen-reader status and reduced motion. Add English plus a second-language test bundle, explicit zone display and local formatting. Test 360px and larger screens.

**Acceptance:** Automated accessibility checks pass; manual keyboard/screen-reader checklist and screenshots recorded; no horizontal overflow or lost error input.

**Required entry points:** `make accessibility-test; make frontend-check`. Implement the commands by the relevant task before claiming these checks passed. Include meaningful unit/integration/browser tests appropriate to the behavior; preserve actual logs in `docs/verification/T30/` and a review packet in `docs/execution/review-packets/T30.md`.

### T31 Versioned blueprint persistence and semantic validation

**Depends on:** T05, T06, T15, T16.  
**Requirement IDs:** R15,R16,R24.  
**Target paths:** modules/blueprints, migrations, contracts/blueprints.  
**Goal and implementation:** Implement schema registry, draft/version persistence, field provenance, semantic resource/schedule/form checks, import/export and schema migration policy. Add server-computed canonical hash and reject unresolved material fields at publish boundary. Extend included starter schema explicitly.

**Acceptance:** Valid synthetic blueprint roundtrips; malformed/foreign resource references and unresolved timezone/duration/capacity are rejected; export contains no credential/customer records.

**Required entry points:** `make blueprint-test; make integration-test`. Implement the commands by the relevant task before claiming these checks passed. Include meaningful unit/integration/browser tests appropriate to the behavior; preserve actual logs in `docs/verification/T31/` and a review packet in `docs/execution/review-packets/T31.md`.

### T32 Booking rehearsal and live change impact

**Depends on:** T07, T09, T10, T31.  
**Requirement IDs:** R18,R19.  
**Target paths:** modules/blueprints/rehearsal and impact reports.  
**Goal and implementation:** Run shared scheduler in isolated synthetic rehearsal storage. Implement published/draft diffs and current future-booking impacts, affected booking versions and expiring impact report. Use scheduling guards for publication race validation.

**Acceptance:** Rehearsal has no real notification/write side effects; reducing hours/capacity identifies impacted bookings; a new conflicting booking invalidates an old report.

**Required entry points:** `make rehearsal-test; make impact-test`. Implement the commands by the relevant task before claiming these checks passed. Include meaningful unit/integration/browser tests appropriate to the behavior; preserve actual logs in `docs/verification/T32/` and a review packet in `docs/execution/review-packets/T32.md`.

### T33 AI builder and conversational customization UI

**Depends on:** T18, T28, T31, T32.  
**Requirement IDs:** R15,R16,R17,R18,R19.  
**Target paths:** AI builder tools and business blueprint screens.  
**Goal and implementation:** Implement description/document extraction, material clarification, source provenance display, structured draft edits, diff/rehearsal/impact preview, owner approval and atomic publication. Render guest preview through trusted components; rollback creates a revalidated new version.

**Acceptance:** Approved exact hash publishes; edited/unapproved draft cannot publish; injected upload cannot grant authority; existing appointments remain intact; preview and published page match validated configuration.

**Required entry points:** `make builder-e2e; make agent-eval; make blueprint-test`. Implement the commands by the relevant task before claiming these checks passed. Include meaningful unit/integration/browser tests appropriate to the behavior; preserve actual logs in `docs/verification/T33/` and a review packet in `docs/execution/review-packets/T33.md`.

### T34 Connector registry and declarative mapping

**Depends on:** T11, T14, T15, T28.  
**Requirement IDs:** R20,R21.  
**Target paths:** modules/integrations registry and portal connection screens.  
**Goal and implementation:** Implement typed connector manifest, lifecycle, permission/mapping preview, connection testing, revoke, encrypted token reference and health. Add signed outbound webhooks and demo CRM sink with retries/inbox, SSRF checks and egress limits. External providers remain selected-adapter extensions.

**Acceptance:** Invalid mapping rejected; revoked connection stops calls; private/redirected webhook targets blocked; duplicate events do not repeat effects; provider/account status correctly labelled.

**Required entry points:** `make connector-test; make business-e2e`. Implement the commands by the relevant task before claiming these checks passed. Include meaningful unit/integration/browser tests appropriate to the behavior; preserve actual logs in `docs/verification/T34/` and a review packet in `docs/execution/review-packets/T34.md`.

### T35 Intent booking experience and protocol client evidence

**Depends on:** T17, T19, T29, T30.  
**Requirement IDs:** R14,R25.  
**Target paths:** guest assistant UI, SSE client and protocol tests.  
**Goal and implementation:** Add optional multilingual intent input, real slot cards, clarification, cancellation of agent run, exact approval display and operation status recovery. Test independent MCP/A2A clients and the configured live local model separately.

**Acceptance:** Critical permission tests all pass; model outage leaves manual booking working; actual live model evidence recorded or NOT_RUN; independent protocol discovery/task/approval evidence exists.

**Required entry points:** `make assistant-e2e; make agent-eval; make agent-live-test; make protocol-test`. Implement the commands by the relevant task before claiming these checks passed. Include meaningful unit/integration/browser tests appropriate to the behavior; preserve actual logs in `docs/verification/T35/` and a review packet in `docs/execution/review-packets/T35.md`.

### T36 Portable templates and safe automation recipes

**Depends on:** T31, T33, T34.  
**Requirement IDs:** R16,R21,R24.  
**Target paths:** blueprint packs and declarative workflow registry.  
**Goal and implementation:** Create reusable low-sensitivity salon/class/rental demo blueprints. Import resolves logical resource keys and connector references into a draft. Implement named trigger-condition-action recipes and mapping preview; AI edits use schema and approval.

**Acceptance:** Portable export/import across two synthetic tenants creates distinct authorized references; no secrets/customer data; unsupported actions and arbitrary executable content rejected.

**Required entry points:** `make blueprint-test; make automation-test`. Implement the commands by the relevant task before claiming these checks passed. Include meaningful unit/integration/browser tests appropriate to the behavior; preserve actual logs in `docs/verification/T36/` and a review packet in `docs/execution/review-packets/T36.md`.

### T37 Disruption and cancellation recovery workflow

**Depends on:** T10, T12, T18, T28, T29, T34.  
**Requirement IDs:** R11,R22.  
**Target paths:** recovery workflow, staff review and guest offer screens.  
**Goal and implementation:** Implement staff absence impact, deterministic replacement search, explainable options, staff-approved notification draft and expiring guest acceptance. FIFO basic waitlist is explicit; optional suggestions respect consent/fairness and cannot auto-move appointments.

**Acceptance:** One claimant per offer; no duplicate outreach under replay; customer original booking is preserved until atomic approved move; declined/expired offers release inventory once.

**Required entry points:** `make recovery-test; make recovery-e2e`. Implement the commands by the relevant task before claiming these checks passed. Include meaningful unit/integration/browser tests appropriate to the behavior; preserve actual logs in `docs/verification/T37/` and a review packet in `docs/execution/review-packets/T37.md`.

### T38 Explainable business insights and product measurements

**Depends on:** T15, T18, T28, T33.  
**Requirement IDs:** R23.  
**Target paths:** authorized metric functions and insights UI.  
**Goal and implementation:** Expose bounded aggregate tools for occupancy/cancellations/no-show and source/period explanations. Add privacy-minimized guest/setup funnel events, opt-out behavior and no raw contact text. Show advice separately from operational commands.

**Acceptance:** Metric results agree with SQL fixtures; tenant bounds enforced; no arbitrary SQL tool; advice does not alter price/staff schedule; analytics does not capture tokens or form contacts.

**Required entry points:** `make reporting-test; make telemetry-test`. Implement the commands by the relevant task before claiming these checks passed. Include meaningful unit/integration/browser tests appropriate to the behavior; preserve actual logs in `docs/verification/T38/` and a review packet in `docs/execution/review-packets/T38.md`.

### T39 Future feature experimental contracts

**Depends on:** T31, T35, T37, T38.  
**Requirement IDs:** R26,R27,R28.  
**Target paths:** experimental multi-stage planner, voice/message ports and advice evaluators.  
**Goal and implementation:** Create flagged same-cell multi-stage scheduling prototype with bounded search/all-or-nothing allocations. Define and test voice read-back/message intent adapter contracts with synthetic media/intents; actual telephony/provider connection remains NOT_RUN. Add duration/demand advice evaluation using synthetic historical labels and owner review.

**Acceptance:** All P3 flags default off; multi-stage failure rolls back all stages; voice/message intents cannot self-confirm; backtest limitations and absence of live provider/model evidence explicitly reported.

**Required entry points:** `make experimental-test; make agent-eval`. Implement the commands by the relevant task before claiming these checks passed. Include meaningful unit/integration/browser tests appropriate to the behavior; preserve actual logs in `docs/verification/T39/` and a review packet in `docs/execution/review-packets/T39.md`.

### T40 Whole application deployment and capacity measurement

**Depends on:** T23, T24, T25, T30, T33, T34, T35, T36, T37, T38.  
**Requirement IDs:** R29,R30.  
**Target paths:** Compose/Helm frontend integration, CI and cost-input worksheet.  
**Goal and implementation:** Deploy websites and application images together with TLS/ingress routing and correct cookie/CORS policy. Run core+builder browser journeys in Compose and kind. Extend load and cost-input model for static/public/API/AI traffic and 1M concurrent sensitivity. Recheck restore and rolling upgrades with frontend/API version compatibility.

**Acceptance:** Local deployments pass actual booking/builder journey; model/load status is separate; recorded achieved throughput includes environment/generator limits; Terraform validation does not claim paid deployment.

**Required entry points:** `make app-e2e; make k8s-smoke; make restore-test; make load-local; make terraform-check`. Implement the commands by the relevant task before claiming these checks passed. Include meaningful unit/integration/browser tests appropriate to the behavior; preserve actual logs in `docs/verification/T40/` and a review packet in `docs/execution/review-packets/T40.md`.

### T41 Independent full application release verification

**Depends on:** T26, T30, T33, T35, T36, T37, T38, T39, T40.  
**Requirement IDs:** R01-R30.  
**Target paths:** final verification matrix and release evidence.  
**Goal and implementation:** Run retained V01–V26 plus A01–A20 against final revision with distinct guests/tenants and real local services. Scan for forbidden real payment dependencies and secret/PII leaks. Record experimental and live-provider/model readiness separately. Fix only demonstrated failures and rerun affected gates.

**Acceptance:** All mandatory P0/P1 local gates have reproducible passing evidence; mandatory blocked gates produce incomplete status; no unsupported production/million-user claim.

**Required entry points:** `make verify-release; make app-e2e; make agent-eval`. Implement the commands by the relevant task before claiming these checks passed. Include meaningful unit/integration/browser tests appropriate to the behavior; preserve actual logs in `docs/verification/T41/` and a review packet in `docs/execution/review-packets/T41.md`.

### T42 Handoff and pilot readiness decision

**Depends on:** T41.  
**Requirement IDs:** R30.  
**Target paths:** docs/verification/final-report.md and operator/developer handbook.  
**Goal and implementation:** Complete start/access, deployment, backup/restore, troubleshooting and remaining-work guides. Reconcile requirements/tasks/ADRs with implementation. Produce versioned readiness report and owner pilot script; list launch-market/account/budget decisions and scope flags still pending. Send concise review packet to ChatGPT for assessed findings, then record owner acceptance.

**Acceptance:** Documented commands match scripts; every readiness label has evidence or limitation; another clean environment can reproduce mandatory local checks; precise next task for any incomplete scope.

**Required entry points:** `make verify-docs; make doctor; make smoke`. Implement the commands by the relevant task before claiming these checks passed. Include meaningful unit/integration/browser tests appropriate to the behavior; preserve actual logs in `docs/verification/T42/` and a review packet in `docs/execution/review-packets/T42.md`.

## Retained operator commands

Implement and document these exact entry points or provide an equivalent cross-platform wrapper with an explicit mapping. Each command must use the chosen environment and return a meaningful nonzero exit code on failure.

```bash
make doctor
make build
make test
make integration-test
make up
make seed
make smoke
make e2e
make agent-eval
make agent-live-test
make protocol-test
make simulator-test
make multicell-up
make migration-test
make helm-check
make kind-up
make k8s-deploy
make k8s-smoke
make recovery-test
make restore-test
make load-local
make terraform-check
make verify-release
make down
```

`make verify-release` runs mandatory available gates, records NOT_RUN/BLOCKED items, and must not return an unconditional success when a required gate fails. Define separate exit/status handling for externally unavailable tests. Heavy scale runs and destructive reset commands require explicit environment parameters and project-scoped guards. Teardown does not delete data volumes by default.

Provide Windows/WSL2 setup guidance, Linux prerequisites, port mappings, minimum measured local resources, model endpoint examples without credentials, and a small memory profile if practical. Do not promise that all optional services fit on an unmeasured machine.


## Complete application definition of done

The retained backend gates V01–V26 and additional A01–A20 in 10_VERIFICATION_AND_TRACEABILITY.md are satisfied for the declared scope on the final source revision. Guest and staff browser journeys, blueprint publication, approval rejection, impact race, restore and real local deployments pass. P3 experiments and external account/live-model/scale/cloud results remain independently labelled.

T41 must return a nonzero verification result when a mandatory local gate fails. NOT_RUN is acceptable for unavailable external test accounts or large-scale/cloud runs only when clearly separated from local completion. The final report lists implemented P0/P1, implemented P2, experimental P3 and deferred provider activation distinctly.

The JSON task index in contracts/tasks.json is navigation metadata. The task prose and specifications supply acceptance semantics; do not replace them with a checkbox-only process.
