# Portable blueprints and publication contract

Status: adopted baseline that fills the missing original starter schema. The files [booking-blueprint.schema.json](../../contracts/booking-blueprint.schema.json) and [salon.blueprint.json](../../examples/salon.blueprint.json) are a new portable starter contract and a synthetic draft example. They are not recovered original attachments or implemented runtime features.

## Portable data and runtime ownership

Portable schema version `1.0.0` describes business display data, logical locations/resources/services/schedules, supported booking policies, low-sensitivity contact forms, trusted page components, provenance and connector references. It contains no tenant ID, live booking, customer contact record, credential, executable script, remote model URL, runtime approval or self-published status. Import always creates a server-owned draft.

The JSON Schema enforces field shapes, supported enums, basic sizes and forbidden unknown properties. It cannot prove IANA zones, currencies, logical reference ownership, schedulability, consistent prices, source provenance coverage, semantic policy compatibility or absence of secrets in arbitrary strings. T31 implements these semantic checks and negative tests in addition to schema validation. Do not call a schema-valid document publishable.

Resolve logical keys inside the tenant during import. Create distinct runtime IDs in each target tenant. Service `published` is desired visibility after authorized blueprint publication, never an instruction to expose an imported draft immediately. Connector `referenceKey` is a placeholder requiring owner consent/mapping; portable content cannot select another tenant's connection. Remove nonportable runtime IDs on export. Schema migrations are explicit, deterministic and reviewed; unknown versions fail safely rather than guessing. Resource/location deletion, requirement changes and duration/zone/capacity changes require impact checks.

This starter expresses default capacity for `SESSION` services, not complete recurring class occurrence templates, schedule exceptions, declarative recipes or every eventual page prop. Actual fixed occurrences remain the authorized capacity domain records in T10. T31/T36 extend the versioned schema explicitly as those portable features are implemented; do not invent unvalidated ad hoc fields. Draft `UNRESOLVED` provenance can mark material questions even when the shape contains provisional values; semantic validation must block publication until they are resolved.

## Material fields and provenance

Every material setting has provenance keyed by its JSON Pointer: source type `SUPPLIED`, `INFERRED` or `UNRESOLVED`, optional synthetic/authorized source label and evidence reference, and human resolution where applicable. Material fields include zone, duration/buffers, resource/occurrence rules, capacity, price/currency, cancellation/advance/contact/payment policy and connector consent/mappings. T31 verifies coverage and pointer existence. Inferred material choices must be visibly reviewed before owner approval; unresolved material fields block publication even if represented as draft metadata or plausible defaults.

Imports/documents/descriptions are untrusted data. Extraction reports supplied facts separately from inference and asks focused questions for material ambiguity. Uploaded content cannot alter roles, approvals, tool permissions or server configuration. Optional branding does not justify inventing missing scheduling facts.

## Draft record and exact hash

Runtime draft record has tenant/draft ID, immutable revision history, optimistic version, schema version, normalized content, provenance, base published version, server-computed hash, validation state, creator/channel and model/prompt/tool versions if AI-assisted. Every edit creates a new revision, invalidates validation/rehearsal/impact/approval derived from old hash and returns to `DRAFT`.

Define a deterministic canonicalization algorithm in T31 shared by persistence/approval verification; document sort/order/numeric/string behavior and test test vectors. Hash only approved semantic content and applicable provenance, excluding unstable timestamps/status/credential references. Server computes the hash; client/model hash is compared, never accepted as authoritative. An approval binds tenant, draft ID/revision/hash, base published version, impact report, actor and expiry.

## Trusted page composition

`page.components` is a list of registry keys with validated props; starter keys are `businessHeader`, `serviceList`, `bookingForm` and `policySummary`. Branding has bounded color tokens and plain-text labels. React renderer escapes plain text. No raw HTML, arbitrary JavaScript, CSS expressions, executable templates or provider fetch URLs are allowed. Forms collect only configured low-sensitivity fields such as name/contact/note with limits; no medical/biometric/card/bank data. Custom components require an ordinary reviewed code change.

Guest draft preview and published website use the same renderer/schema/client boundary. Tests compare preview and published configuration, props and behavior; real browser screenshots/keyboard/mobile checks verify fidelity. Preview cannot submit real customer bookings by accident; draft rehearsal uses isolated synthetic routes/storage. Publication changes only validated current configuration, not historic accepted policy snapshots.

## Rehearsal

Run the actual scheduler code against an isolated synthetic dataset, clock and event sink. Cover routine hours, holidays, overnight schedules, buffers, multi-resource requirements, DST gaps/overlaps, expiry, capacity last-seat contention and failed reschedule. No live notification, calendar export, webhook or real tenant booking write occurs. A rehearsal result includes draft hash, scheduler/schema version, input fixtures, expected/actual results and failures. It explains behavior; it does not replace database concurrency/security gates.

## Impact and atomic publication

Impact report contains draft hash, current published version, current scheduling guard revision, affected booking IDs/versions (protected staff-only), categorized proposed conflicts and expiry. Compute additions/removals, changes in availability/capacity/policies and consequences for future bookings. A new inventory/config/external-busy mutation advances the guard and invalidates an earlier report, even if its booking was not in the old affected list.

Publish transaction uses the domain lock order: tenant fence → scheduling guard → affected resources/occurrences/bookings. Re-read base version, exact draft hash/schema semantics, report expiry/guard/booking versions and owner client approval. If anything changed, return `409 IMPACT_STALE` or `412 VERSION_CONFLICT` and request a fresh preview; no silent partial publication. Persist active version/config update, audit, outbox/cache invalidation, guard increment and operation result together.

If the proposed configuration conflicts with existing confirmed bookings or reduces capacity below active inventory, block automatic publication until an explicit impact-resolution policy is satisfied. Proposed recovery actions remain separate approvals/atomic moves; publication never cancels or moves guests implicitly. Existing accepted snapshots and allocations remain intact. Rollback copies a previous config into a new draft and reruns validation/rehearsal/current impact/owner approval; it is not a database rewind.

## Automation and connector mapping

Recipes are registry-based trigger/condition/action data. Allowed actions reference authorized domain ports and have separate consent/budget/idempotency guards. No arbitrary code, shell, SQL, transformation expression or URL fetch tool. AI may suggest a recipe or field mapping, then owner sees exact versioned diff and synthetic payload preview.

Signed outbound webhooks validate protocol/host/port/DNS and redirect policy, block private/link-local/loopback destinations outside explicit local-demo exceptions, and enforce egress limits at resolution and connection. Redirects cannot bypass destination checks. Tokens remain encrypted connection references outside export and model context. Revocation cancels future dispatch, with provider-in-flight ambiguity recorded.

## Acceptance boundary

T31 proves portable roundtrip, malformed/unresolved/foreign-reference rejection and safe export. T32 proves isolated rehearsal, affected-booking detection and stale impact race. T33 proves exact owner approval, hostile upload rejection, unchanged existing appointments and preview/published fidelity. T36 proves import across two synthetic tenants produces distinct authorized IDs, supported declarative recipes only and no secret/customer leak. Live external providers and actual model use have separate evidence labels.
