# Typed API and tool baseline

Status: proposed endpoint baseline adopted for implementation. Existing exact endpoint paths in backend plan section 7 are retained. Paths/shapes added here make missing operations precise; they are not a claim that routes or generated OpenAPI exist. T02 generates runtime OpenAPI from typed contracts and records any reviewed adjustment. Frontend clients and model tool schemas must derive from those same contracts.

## Wire and error rules

Use `/v1` JSON APIs with typed UUID IDs, RFC3339 instants including offset, IANA `displayZone`, integer minor-unit amounts and opaque pagination cursors. Never accept tenant, role, approval state, authoritative price or cell route from a model/request body as authority. Unknown material fields are rejected. Model and provider base URLs are operator configuration.

All state-changing domain operations require `Idempotency-Key` and `clientOperationId` generated before the request. Include expected aggregate version for updates; use `If-Match` where applicable. Return `201` for created resources, `200` for completed/replayed outcomes, `202` for genuinely persisted in-progress work, and `204` for successful no-body operations. Every response has a correlation ID. Operation results include `operationId`, `status`, a scoped result reference or stable error, and `replayed` where useful. Do not expose bearer capabilities in generic operation results.

```json
{
  "type": "urn:booking:error:inventory-conflict",
  "title": "The requested time is no longer available",
  "status": 409,
  "code": "INVENTORY_CONFLICT",
  "correlationId": "opaque-correlation-id",
  "operationId": "client-generated-uuid",
  "retryable": false,
  "violations": []
}
```

Safe messages never include foreign-tenant existence, credentials, raw contact text or SQL/provider error internals. `400` is malformed input, `422` is structurally valid but invalid domain terms, `401` is missing/invalid credential, `403` is denied known actor permission, `404` hides inaccessible guest/tenant-owned objects, `409` is inventory/state/idempotency/stale proposal conflict, `412` is expected-version mismatch, `429` is admission quota with bounded `Retry-After`, `503` is required dependency unavailable. Do not endlessly retry `409/412/422`; acquire fresh proposal or resolve the issue. A client that times out queries its operation and repeats only the same key/payload if needed.

## Principal types

| Principal | Grants |
| --- | --- |
| Public | Published catalogue and bounded availability only |
| Guest session | Own proposals, holds and booking creation within one tenant; minimized contact handling |
| Booking-management session | Read/manage specifically granted booking(s); not other guests' holds or arbitrary tenant appointments |
| Waitlist-offer session | Read/accept/decline the named unexpired offer only |
| Business `OWNER` | Tenant catalogue/settings/blueprints and membership actions, subject to audited restrictions |
| Business `MANAGER` | Authorized locations, operations and configured settings; no owner grants or blueprint publication by default |
| Business `STAFF` | Assigned resource/location operations, attendance and explicitly permitted manual booking; no role/config escalation |
| Platform/demo operator | Narrow provisioning/migration or simulator scenario controls; no implicit customer-data access |
| Scoped service identity | Named internal action for tenant/current epoch, not global public administration |

Cookie browser mutations require CSRF and configured origin checks. CLI bearer grants have explicit scopes. OIDC staff tokens are verified against issuer/audience/signature/time and current stored membership. Distinguish login identity from tenant membership; no identity-provider outage should block the default guest free-booking path.

## Core data shapes

| Contract | Material fields |
| --- | --- |
| `AvailabilitySearch` | `serviceId`, `locationId`, start/end instants or explicit resolved date+zone, `partySize`, optional authorized staff/resource filters, limit/cursor |
| `SlotCandidate` | Opaque candidate ID, service/location, appointment and occupied interval, resource IDs or occurrence, party size, display zone, config revision, advisory expiry |
| `ProposalRequest` | Selected candidate/explicit validated selection for `BOOK/RESCHEDULE`, or original booking/version for `CANCEL`; no client-authoritative amount |
| `ProposalView` | ID, immutable material terms, server hash/version, quote expiry, policy text/version, price/currency, payment requirement, explanation |
| `HoldRequest/View` | Proposal ID/hash; result hold ID/status/deadline; no promise beyond deadline |
| `ApprovalRequest/View` | Exact proposal ID/hash/purpose and acknowledgement of displayed terms; result approval ID/owner/deadline |
| `ConfirmBookingRequest` | Proposal ID/hash, active hold ID, approval ID, contact reference and operation ID; simulator reference only where configured |
| `BookingView` | Persisted booking/reference/version/state, accepted terms, management actions, safe confirmation/ICS links |
| `RescheduleRequest` | Original booking/version, new proposal/hash and approval ID; no required independent target hold |
| `BusinessWrite` | Entity fields with expected version; server checks referenced entity ownership and assignment |
| `AgentRunRequest` | Role, bounded user intent/context references; actor/tenant supplied outside model-controlled payload |
| `BlueprintPublishRequest` | Draft/hash/base config version, impact report ID, owner approval ID and operation ID |

Initial limits are configuration with explicit profile values: bounded search dates/result count, hold lifetime/count, input length, export dates/rows, model tokens/tool turns/concurrency and queue length. T03/T08/T16 pin and test chosen values. No unbounded request is accepted because the schema omitted a maximum.

## Guest and public operations

| Endpoint | Request → result | Auth and required behavior | Stable domain errors |
| --- | --- | --- | --- |
| `GET /v1/public/businesses/{slug}` | Published business/location/service view | Public; slug resolves tenant/cell; no private staff contacts | `NOT_FOUND` |
| `GET /v1/public/businesses/{slug}/services` | Filter/cursor → published services | Public; archived unpublished entries absent | `INVALID_FILTER` |
| `POST /v1/public/businesses/{slug}/guest-sessions` | Minimal optional contact/locale → scoped session | Public bounded creation; secure cookie or explicitly selected bearer response | `QUOTA_EXCEEDED` |
| `POST /v1/public/businesses/{slug}/availability/search` | Search → candidate page | Public; bounded advisory search, exact timezone behavior | `INVALID_RANGE`, `AMBIGUOUS_TIME`, `INVALID_PARTY_SIZE`, `CALENDAR_STALE` |
| `POST /v1/guest/proposals` | Selection → immutable proposal | Owned guest session; validate tenant/references/terms | `SLOT_STALE`, `INVALID_REFERENCE`, `POLICY_REJECTED` |
| `GET /v1/guest/proposals/{id}` | ID → exact proposal | Owning grant only | `NOT_FOUND` |
| `POST /v1/guest/holds` | Proposal/hash → hold | Guest; atomic full allocation, quota/deadline/current terms | `INVENTORY_CONFLICT`, `PROPOSAL_STALE`, `QUOTE_EXPIRED` |
| `DELETE /v1/guest/holds/{id}` | Operation metadata → release result | Owning grant; idempotent once-only release | `NOT_FOUND`, `STATE_CONFLICT` |
| `POST /v1/guest/proposals/{id}/approve` | Exact hash/purpose → approval | Client guest session + CSRF; inaccessible to model tool list | `PROPOSAL_STALE`, `QUOTE_EXPIRED` |
| `POST /v1/guest/bookings` | Confirmation → persisted booking | Owner, unexpired hold, exact approval; free policy independent of simulator | `HOLD_EXPIRED`, `APPROVAL_REQUIRED`, `APPROVAL_MISMATCH`, `SIMULATION_PENDING` |
| `GET /v1/guest/operations/{id}` | Client operation ID → persisted status/result | Same scope/actor; absent or inaccessible returns same safe response | `NOT_FOUND` |
| `POST /v1/guest/token-exchange` | Public business slug plus body/header management fragment secret → scoped session | Resolve slug server-side before scoped hash lookup; rate limited, expiry/revocation; clear fragment in frontend | `INVALID_CAPABILITY`, `QUOTA_EXCEEDED` |
| `GET /v1/guest/bookings/{id}` | ID → booking/actions | Booking-management grant or original authorized session | `NOT_FOUND` |
| `GET /v1/guest/bookings/{id}/calendar.ics` | ID → escaped ICS | Same management scope or specifically expiring export grant | `NOT_FOUND` |
| `POST /v1/guest/bookings/{id}/cancel` | Expected version/reason; exact cancellation approval for agent channel → booking | Policy-aware one-time release, audit and suppression; manual client command is explicit authority, agent cannot infer it | `POLICY_REJECTED`, `VERSION_CONFLICT`, `APPROVAL_REQUIRED` |
| `POST /v1/guest/bookings/{id}/reschedule-proposals` | Target selection/version → proposal | Management scope; target advisory; exact before/after view | `VERSION_CONFLICT`, `POLICY_REJECTED` |
| `POST /v1/guest/bookings/{id}/reschedule` | Approved move → booking | Atomic swap; failure retains original | `INVENTORY_CONFLICT`, `APPROVAL_MISMATCH`, `VERSION_CONFLICT` |
| `POST /v1/guest/booking-recovery` | Contact/business reference → generic accepted response | No existence leak; rate-limited one-time link through configured contact channel | `QUOTA_EXCEEDED` |
| `POST /v1/guest/waitlist-entries` / `DELETE /v1/guest/waitlist-entries/{id}` | Desired service/window/party/consent → entry | Guest owner; explicit FIFO basic policy, bounded rows | `INVALID_RANGE`, `NOT_FOUND` |
| `GET /v1/guest/waitlist-offers/{id}` / `POST .../{id}/accept` / `POST .../{id}/decline` | Scoped offer/approval → normal booking outcome or release | Offer capability; unexpired single claimant; accept same booking rules | `OFFER_EXPIRED`, `OFFER_CLAIMED`, `APPROVAL_REQUIRED` |

Token recovery need not impose universal email verification. If tenant policy requires a code, add bounded `contact-verifications` start/verify operations with local inbox tests; never synthesize a customer account to implement the guest flow.

## Business operations

Use `/v1/business/tenants/{tenantId}` consistently. Path tenant is a selector and must match current membership; it is not a trust boundary by itself. A parent list/detail/update path must check all referenced child resources.

| Endpoint group | Request → result | Scope and key behavior |
| --- | --- | --- |
| `POST /v1/business/tenants` | Onboarding → tenant/membership/provisioning operation | OIDC; idempotent owner grant, provisioned route/fence, no cross-tenant existing owner takeover |
| `GET .../{tenantId}/memberships`; `POST/PATCH/DELETE .../memberships/{id}` | Membership commands → versioned state | Owner only by default; prevent final-owner removal and staff self-escalation |
| `GET/POST/PATCH/DELETE .../locations`, `services`, `resources`, `schedules`, `exceptions`, `policies` | Typed fields/version → versioned entity | Owner/allowed manager; staff reads scoped subset; archived referenced entities remain in history |
| `GET .../bookings` / `GET .../bookings/{id}` | Bounded date/resource/state filters → booking list | Authorized location/resource scopes; no unlimited export disguised as list |
| `POST .../booking-proposals`; `POST .../booking-proposals/{id}/approve`; `POST .../bookings` | Manual selection/exact client approval → persisted booking | Staff permission checked; same allocation/current policy/idempotency guarantees |
| `POST .../bookings/{id}/cancel`, `reschedule-proposals`, `reschedule` | Versioned command → booking | Same atomic domain commands; calendar drag opens review/approval |
| `POST .../bookings/{id}/check-in`, `complete`, `no-show` | Expected version → attendance state | Scoped staff; legal transition/clock checks |
| `GET/POST/PATCH .../capacity-occurrences` | Fixed session/capacity → occurrence | Owner/manager; reserved-count constraints; room/instructor allocated once per occurrence |
| `GET .../waitlist-entries`, `POST .../waitlist-offers` | Queue/view or policy-based offer → persisted offer | Authorized operator; expiring inventory/grant; no overselling |
| `GET .../reports/{reportType}`; `POST .../exports`; `GET .../exports/{id}` | Named bounded aggregate/export → result | Utilization/bookings/cancellations/no-show; scoped expiry and synthetic simulator totals separate |
| `GET .../audit-events`; `POST .../customer-data-requests` | Bounded filter/export/erasure → controlled job | Authorized role, retention rules preserve active allocations/audit obligations |
| `GET .../issues`; `POST .../recovery-drafts`; `POST .../recovery-drafts/{id}/approve` | Persisted disruption → proposed options/outreach | Scoped staff approval; guest separately approves move; no automatic relocation |

Shared errors: `INVALID_REFERENCE`, `VERSION_CONFLICT`, `STATE_CONFLICT`, `POLICY_REJECTED`, `APPROVAL_REQUIRED`, `INVENTORY_CONFLICT`, `WRITER_FENCED`, `QUOTA_EXCEEDED`. Match authorization/membership tests to each route group.

## Blueprint, connector and AI operations

| Endpoint group | Request → result | Guard |
| --- | --- | --- |
| `GET/POST .../blueprints`; `GET/PATCH .../blueprints/{id}` | Portable content/draft version → server-owned draft | Authorized draft editing; schema/semantic checks; expected version |
| `POST .../blueprints/{id}/validate`, `/rehearsals`, `/impact-reports` | Draft/hash → validation/synthetic rehearsal/current impact | Isolated rehearsal; no live messages; report binds base/guard/booking versions |
| `GET .../blueprints/{id}/preview` | Draft → trusted preview data | Same renderer used on published guest page; no executable generated content |
| `POST .../blueprints/{id}/approve`; `POST .../blueprints/{id}/publish` | Exact hash/impact → approval then active version | Owner client only; recheck exact terms/fence/guard under locks; atomic publication |
| `POST .../blueprints/{id}/rollback-drafts`; `POST .../blueprints/import`; `GET .../blueprints/{id}/export` | Prior/portable config → new draft or sanitized export | Rollback/import never self-publish; resolve logical keys; remove secrets/customers/runtime IDs |
| `GET .../connectors`; `POST .../connections`; `POST .../connections/{id}/test`; `DELETE .../connections/{id}` | Typed manifests/permissions/mappings → health/lifecycle | Owner consent, encrypted token reference; revoked connection stops egress |
| `POST .../calendar-connections/{provider}/authorization`; provider callback; `GET .../calendar-connections/{id}` | State/PKCE flow → connection/sync status | Verified callbacks, least scopes, encrypted credentials; route details fixed in T14 contract |
| `GET/POST/PATCH .../automation-recipes`; `POST .../automation-recipes/{id}/approve` | Typed trigger/condition/action → versioned recipe | Trusted registry only; synthetic mapping preview, owner approval; no arbitrary code |
| `POST /v1/guest/agent-runs`; `POST .../{tenantId}/agent-runs` | Bounded intent/role → persisted run | Trusted actor/tenant bound externally; explicit model failure, no hidden fallback |
| `GET /v1/guest/agent-runs/{id}` / business equivalent | ID → run/checkpoint | Owner scope; only safe structured data |
| `GET .../agent-runs/{id}/events` | SSE with `Last-Event-ID` → persisted event sequence | Scoped authentication, resumable status, heartbeat/deadline; redacted tokens |
| `POST .../agent-runs/{id}/cancel` | Versioned request → stopped run | Bounded cancellation; committed operations remain queryable |
| MCP tools / A2A Agent Card and tasks | Current protocol contracts → same authorized operations | T19 pins official version/endpoints, independent client evidence; do not replace with invented JSON |

Blueprint errors add `SCHEMA_INVALID`, `UNRESOLVED_MATERIAL_FIELD`, `FOREIGN_REFERENCE`, `DRAFT_STALE`, `IMPACT_STALE`, `APPROVAL_MISMATCH`, `EXECUTABLE_CONTENT_REJECTED`. Connector errors add `MAPPING_INVALID`, `CONSENT_REQUIRED`, `CONNECTION_REVOKED`, `DESTINATION_REJECTED`, `PROVIDER_UNAVAILABLE`. SSE/run errors add `MODEL_UNAVAILABLE`, `MODEL_LIMIT`, `TOOL_BUDGET_EXCEEDED`, `RUN_CANCELLED`.

## Internal and simulator operations

`GET /actuator/health/liveness` and readiness expose appropriate health only; metrics/diagnostics have controlled local/internal access. Internal workflow commands, callback receivers and migration controls require narrowly authenticated audiences and current writer epoch. Public Internet access is not implied by a development route.

The simulator exposes typed create/get/cancel intent and request-refund operations using server-approved money/proposal. Its callback receiver validates raw-body signature/timestamp, deduplicates event ID, and calls authorized simulator reconciliation. Scenario controls require a dedicated demo operator in local/test/demo profiles; guests cannot choose outcomes. Every result includes `simulation=true` and `sim_` references. Ordinary free confirmation has no simulator dependency. T13 fixes final internal paths in generated OpenAPI; no real provider route is allowed.

## Model tool allowlist

| Role | Allowed tools | Additional approval boundary |
| --- | --- | --- |
| Booking | `catalog.lookup`, `availability.search`, `proposal.prepare`, `hold.create`, `booking.confirm`, `operation.read`, scoped management proposal/cancel/move tools | Existing exact guest client approval required for booking/move/cancel; hold creation is bounded provisional inventory only |
| Setup/builder | `blueprint.draft`, `blueprint.validate`, `blueprint.rehearse`, `blueprint.impact`, `blueprint.preview`, `blueprint.publish` | Exact owner approval created outside model; cannot grant roles/connect accounts |
| Recovery | `issue.read`, `replacement.search`, `recovery.draft`, approved outreach/offer operation, simulated compensation/status | Staff approves outreach/action; guest approves their move; no real refunds |
| Insights | Named metric functions with bounded filters | Read-only advice; no arbitrary SQL or settings mutation |

The model supplies typed task arguments only; gateway supplies actor, tenant, route, actor channel and approval capability from trusted runtime context. The model cannot label an agent call as a direct client action. Manual cancellation can use the explicit scoped client command itself as authority; agent cancellation requires a client-created `CANCEL` proposal approval bound to booking/version/current policy. Parse/schema/authorization checks run even for apparently valid model output. Tool timeout means uncertain outcome and triggers lookup before retry. Completion language is based on persisted booking/operation result. Uploaded descriptions, calendar event text and connector data are untrusted content, never new tool permissions.
