# Domain and persistence contract

Status: adopted implementation baseline. This specifies behavior to implement and test; SQL fragments illustrate constraints and are not delivered migrations.

## Types and authority

Use distinct Java value types for `TenantId`, `CellId`, `LocationId`, `ServiceId`, `ResourceId`, `GuestSessionId`, `ProposalId`, `HoldId`, `ApprovalId`, `BookingId`, `OperationId`, `BlueprintId` and `AgentRunId`. UUID is a suitable wire representation; equality of wire IDs never grants authorization. Store `Money(amountMinor: long >= 0, currency: supported ISO code)` without floating point. Validate currency-specific minor-unit rules in the server.

`TrustedActorContext` contains authenticated principal/grant ID, resolved tenant, roles, permitted location/resource scopes, channel and correlation ID. It is created by security adapters and cannot be deserialized from a model or ordinary request body. `WriterContext` contains server-resolved cell and expected route epoch. Business writes use current membership checks. System jobs use scoped service identities, never a broad implicit system bypass.

Store UTC instants in `timestamptz`; preserve location IANA zone, explicit accepted offset where applicable and policy snapshot. Recurring hours are local date/day/time rules, including explicitly represented overnight intervals. Use half-open occupied intervals `[appointmentStart - beforeBuffer, appointmentEnd + afterBuffer)`. Reject unbounded/empty ranges and nonpositive duration. An ambiguous local time requires a valid offset or clarification; a nonexistent local time is rejected. Render the location zone explicitly in both frontends.

## Minimum persistent records

Every cell tenant-owned table has `tenant_id NOT NULL`, a tenant-aware primary/unique key, matching composite foreign keys and RLS. IDs in this table are typed, with `(tenant_id, id)` relationships unless noted.

| Record | Essential fields and constraints |
| --- | --- |
| Directory tenant/route | Public slug unique; home cell; monotonically increasing epoch; migration state; resides in separate directory store |
| `tenant_writer_fence` | Tenant, epoch, `WRITABLE/FROZEN/RETIRED`; locked and checked by every write |
| Membership | Principal issuer/subject, tenant, role, active state, optional location/resource scope, version |
| Location | Name, IANA zone, address/public fields, archived state, version |
| Service | Location, duration/buffers, price/currency, published/archived state, policy version, requirements, version |
| Resource and requirement | Exclusive resource, authorized staff link; service requirement options, quantity and compatible location |
| Schedule/exception | Resource/location, local recurring intervals, date exceptions/leave/holiday, version |
| `tenant_schedule_guard` | Tenant and monotonic revision covering all inventory/config/external-busy mutations |
| Guest session/grant | Hash of >=128-bit random secret, scope, tenant, optional booking/offer, expiry/revocation, minimized encrypted contact reference |
| Proposal | Guest/actor, operation kind, immutable canonical terms, server hash, config/guard revisions, expiry, optional original booking/version |
| Approval | Proposal/hash, actor/grant, purpose, expiry, recorded source/client request; uniqueness prevents contradictory reuse |
| Hold | Proposal, owner, deadline, `ACTIVE/CONSUMED/EXPIRED/RELEASED`, version; unique active ownership rules |
| Booking | Owner/contact reference, public reference, accepted immutable proposal/policy, state, version, attendance/audit links |
| Exclusive allocation | Resource, occupied `tstzrange`, hold/booking owner links, `HELD/CONFIRMED/RELEASED/EXPIRED`; bounded nonempty range |
| Capacity occurrence | Service, fixed instant interval, positive capacity, reserved count `0 <= reserved <= capacity`, version |
| Capacity allocation | Occurrence, party size, hold/booking links and active/released state; one persisted accounting contribution per reservation |
| Operation | Tenant, actor/grant scope, operation type, idempotency key, canonical request hash, client operation ID, terminal result/error reference |
| Inbox/outbox | Provider/consumer/event unique IDs; versioned event schema, correlation, payload references, lease/retry/dead-letter metadata |
| Notification/start job | Booking/version, type/time, unique semantic key, workflow ID, `PENDING/SENT/FAILED/UNKNOWN/SUPPRESSED` |
| Waitlist entry/offer | Service/window/party, consent, FIFO ordinal, offer grant/deadline, hold link, unique active offer claim |
| Calendar connection/event | Provider account/resource mapping, encrypted credential reference, scopes, sync cursor/freshness, event provenance and versions |
| Blueprint/version/impact | Schema version, immutable content/hash, provenance, draft base version, guard revision, affected booking versions and approval |
| Agent run/checkpoint | Actor/tenant, role, model/prompt/tool versions, limits, durable sequence, operation IDs, status and failure |
| Simulator intent/refund | `sim_` ID, `simulation=true`, authoritative proposal money, terminal state, unique idempotency/event IDs |
| Audit/export/retention | Actor/action/target/outcome/channel; scoped export expiry; retention policy/version; no bearer secrets |

Customer contacts, model credentials and calendar tokens must not be copied into proposals, events, blueprints or logs. Encrypt credentials and retained contact data according to deployment key configuration. Generic idempotency result rows contain no raw grants; sensitive result recovery uses an encrypted, narrowly scoped store or separately recoverable token exchange flow.

## I01 — Tenant isolation and database access

Use separate migration-owner and runtime roles; runtime is neither superuser, table owner nor `BYPASSRLS`. Enable and force RLS, restrict table grants, and prevent runtime role inheritance from elevated roles. Establish transaction-local context with a parameterized call before any tenant query:

```sql
SELECT set_config('app.tenant_id', :trusted_tenant_id, true);
-- Representative policy, installed per tenant table:
CREATE POLICY tenant_scope ON bookings
  USING (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid)
  WITH CHECK (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid);
```

No context defaults to deny. Test both successful/failed transactions, pooled connection reuse, background jobs and unset context using the actual runtime role. RLS complements endpoint ownership and tenant-aware foreign keys. Privilege checks prevent role/tenant reassignment through mass assignment. Public DTOs omit private fields. Translate constraint errors without disclosing whether foreign-tenant objects exist. PostgreSQL documents owner/bypass exceptions and integrity-check visibility separately; see [row security policies](https://www.postgresql.org/docs/current/ddl-rowsecurity.html).

## I02 — Exclusive inventory

All active holds and confirmed appointments consume the same allocation table. Migration baseline:

```sql
CREATE EXTENSION IF NOT EXISTS btree_gist;
-- Add to the allocation table after defining tenant/resource/range/state columns:
CONSTRAINT no_exclusive_overlap EXCLUDE USING gist (
  tenant_id WITH =,
  resource_id WITH =,
  occupied WITH &&
)
WHERE (state IN ('HELD', 'CONFIRMED'))
DEFERRABLE INITIALLY IMMEDIATE;
```

Also constrain finite nonempty `[)` bounds and enforce owner references/allowed state transitions. Never use `now()` in the active-row predicate. Expired holds are transitioned explicitly. Do not partition active allocations by date or replace PostgreSQL with a distributed layout without proving the invariant. Exclusion constraints with range overlap and scalar `btree_gist` equality are supported PostgreSQL mechanisms; see [range constraints](https://www.postgresql.org/docs/current/rangetypes.html#RANGETYPES-CONSTRAINT).

## I03 — Capacity inventory

One capacity occurrence row serializes accounting. Under its lock, an atomic conditional update adds party size only if `reserved + partySize <= capacity`; persist the allocation in the same transaction. Holds and confirmed bookings both count. Hold conversion changes its state/owner, not the count. Release updates an active allocation once and decrements only when that transition occurred. Never infer capacity from Redis or an unlocked `COUNT`. Reconciliation compares counter to active allocation sum and alerts; it cannot silently correct away a valid guest booking.

If a class uses a room/instructor, the occurrence owns one exclusive interval for those resources. Each guest reserves seats in the occurrence; do not create overlapping instructor allocations per seat. Capacity reduction below reserved inventory fails or enters explicit impact resolution; no guest is silently displaced.

## I04 — Stable locking and authoritative time

Global initial lock order for a tenant command: writer fence → tenant scheduling guard → resource IDs sorted ascending → occurrence IDs sorted ascending → hold/booking IDs sorted ascending. Ensure every applicable mutation, expiry, calendar sync and blueprint publication follows it. If earlier inspection is needed to find rows, re-read all authoritative values after locking. Keep transactions short and bounded.

Use database time sampled after acquiring the relevant locks for quote/hold/approval deadlines. `transaction_timestamp()` alone can be stale after lock waits; use a writer clock query that observes current time after locking. Deadline equality means expired. Test a request that enters before expiry but obtains its lock after expiry.

## I05 — Proposed terms and approvals

Proposal material terms include tenant, service/location, resource set or occurrence, party size, appointment and occupied instants, display zone/offset, amount/currency, payment requirement, policy/config versions, operation purpose, original booking/version if any, and expiry. The server canonicalizes and hashes this immutable object using a documented deterministic algorithm. Changed material terms produce a new proposal/hash and invalidate previous approval.

Only a client approval endpoint authenticated as the applicable guest or authorized business actor can create approval. Approval records exact proposal hash/purpose/owner/deadline. A tool may consume an existing approval ID after server validation; no model tool creates one. A natural-language “yes” in an agent transcript is input to a UI review step, never authority by itself. Agent cancellation also requires exact client-created `CANCEL` approval bound to original booking/version/current cancellation terms. A direct management UI cancellation command can itself be the explicit authorized client action; trusted adapters bind channel so an agent cannot impersonate it.

New guest booking requires current owned hold plus exact approval. Proposals and availability are advisory before a hold. Optional contact verification is tenant-configured, bounded and does not create an account. Hold protection lasts only until its declared deadline, including any pending verification/simulated-payment wait.

## I06 — Idempotency and atomic result

Scope key uniqueness by `(tenant, actor-or-grant-scope, operationType, idempotencyKey)`. Persist canonical request hash and terminal result/error. The client generates the key and `clientOperationId` before sending. Identical retries return the original terminal result; changed payload produces `409 IDEMPOTENCY_MISMATCH`. Operation lookup is scoped to the same actor/grant and never proves nonexistence across tenants.

Claim the operation inside the business transaction using database uniqueness/locking. Concurrent duplicates wait boundedly or receive `202 IN_PROGRESS` with the same operation ID; they cannot run an independent command. Business changes, outbox and terminal operation result commit together. For a known domain rejection use a savepoint after the operation claim, roll back only domain changes, then persist the rejection result. Unexpected transaction/connection failure is unresolved until lookup/retry with the same key; do not issue a new key or assert success. T09 must test this storage strategy, including PostgreSQL statement-abort behavior.

## I07 — Reservation algorithms

**Create hold:** authenticate/resolve caller → claim operation → lock fence/guard/resources/occurrence → verify revisions, service policy and database time → expire relevant old holds under those locks → revalidate schedules/external-busy/capacity → atomically reserve every required resource/party place → persist hold/job/outbox/result → increment guard revision → commit. Failure leaves no partial allocation. Stored proposal revision is revalidated; unrelated inventory revision changes may permit a fresh check, while changed material configuration requires a new proposal.

**Confirm:** lock the same coordination rows plus hold → check owned active hold and all deadlines using post-lock time → validate exact approval, contact policy and optional simulated-deposit status → preserve occupied inventory while converting held allocations to confirmed booking ownership → persist booking, management grant recovery reference, notification/start jobs, outbox and result → commit. Return confirmed only from a committed booking response.

**Expire/release/cancel:** lock and transition the active source once → decrement capacity only for a changed allocation → release exclusive allocations → suppress applicable pending reminders → write event/audit/result and guard revision. Duplicate expiry/cancel is harmless. Keep historical booking and policy snapshots readable.

## I08 — Atomic rescheduling

Create an immutable reschedule proposal referring to the original booking/version. It is advisory and does not independently hold a target that may overlap the booking's existing resource allocation. Show that risk clearly in the UI. Client approves the exact changed terms, then the server performs one transaction:

1. Claim operation; lock fence, guard, the union of old/new resources/occurrences and original booking in the fixed order.
2. Re-read original booking/version, current target schedule, deadlines/policy and exact approval. Expire relevant target holds.
3. Where old/new occupied intervals overlap on the same resource, defer only the named exclusion constraint for this transaction. Release/update the old allocation and insert/update the complete target allocation set; for capacity, apply the net change under occurrence locks.
4. Verify final resource/capacity state, update booking/version/snapshot, write outbox and result, and force the deferred constraint check before marking success.
5. Commit all changes. Any inventory/constraint failure rolls back the move and preserves the original booking/allocation/version.

Never cancel the old booking in a separate transaction before acquiring the target. Recovery offers can use ordinary expiring target holds where they do not conflict with the original; overlapping candidates use the same advisory atomic-move path. Cross-tenant/cell moves are unsupported. This adopted resolution fills a gap in the original plans and must receive targeted T09 review.

## I09 — State machines

| Aggregate | Legal baseline transitions | Guards |
| --- | --- | --- |
| Hold | `ACTIVE → CONSUMED / EXPIRED / RELEASED` | Deadline/ownership; terminal state cannot reserve again |
| Booking | `CONFIRMED → CHECKED_IN → COMPLETED`; `CONFIRMED → CANCELLED / NO_SHOW` | Authorized actor, policy/current time, expected version; any additional operator override is explicit and audited |
| Proposal/approval | Immutable; valid until deadline/revocation/changed terms | Exact actor/hash/purpose; booking result consumes the relevant approval |
| Waitlist offer | `OFFERED → ACCEPTED / EXPIRED / DECLINED / REVOKED` | One claimant, scoped grant, active offer hold or declared advisory policy |
| Agent run | `QUEUED → RUNNING → INPUT_REQUIRED / SUCCEEDED / FAILED / CANCELLED`; `INPUT_REQUIRED → RUNNING` | Stored sequence and budget; cancellation cannot roll back an already committed booking |
| Blueprint draft | `DRAFT → VALIDATED → APPROVAL_REQUIRED → PUBLISHED`; edits return to draft | Exact hash/base version/impact/owner approval; server-owned state |
| Simulated intent | `CREATED → PENDING → SUCCEEDED / DECLINED / CANCELLED` | Signed/deduplicated events; terminal event precedence prevents regression |

Rescheduling retains booking identity and increments version rather than inventing a cancellation. Reports define treatment of checked-in/completed/no-show rows. Simulator compensation is a separate refund state machine; no value in this table represents actual collected revenue.

## I10 — Side effects and providers

Outbox IDs and consumer inbox uniqueness prevent duplicate domain effects under at-least-once delivery. Activity/workflow IDs derive from tenant, aggregate and action/version. Provider calls use bounded retries and recorded ambiguity. Reminder dispatch rechecks booking status/version so cancellation suppresses unsent messages. No guarantee can retract an already accepted provider send.

Calendar event/cursor writes acquire the schedule guard and update its revision. Required stale-source policy can restrict new holds; existing confirmed bookings remain intact. External edits that conflict create persisted staff resolution cases; remote calendars and local PostgreSQL do not share an atomic transaction.

Simulator-only `PaymentGateway` port uses server-derived proposal amount and idempotency. All response/events have `sim_` IDs and `simulation=true`; receipts say `SIMULATED — NO MONEY MOVED`. Dedicated operator chooses scenarios in local/test/demo profiles only. Signed raw-body callback validation and durable inbox precede effects. Late success after inventory release leads to compensating simulated refund, never stealing inventory. Real gateway configuration, SDKs, card/bank fields and provider egress are prohibited.

## I11 — Cell migration

Freeze writer fence; drain in-flight commands; copy a consistent tenant snapshot including grants, operation results, approvals, pending jobs/outbox/inbox and workflow-routing state; reconcile counts/checksums/invariants; switch directory epoch; activate destination fence; retain source as retired. A planned pause is permitted. Delayed source callbacks/jobs must resolve the current route and cannot mutate a retired fence. Only one cell is writable at any point. Migration/backup roles are separate and cannot be accessed by model tools.

## I12 — Verification obligations

Real PostgreSQL tests must prove RLS, pooled-context isolation, direct SQL exclusion failures, multi-resource rollback, >=100 simultaneous exclusive attempts, N+ capacity requests, deadline-after-lock rejection, same-key retry/mismatch, original-preserving failed/overlapping reschedule, cancellation/expiry duplicate release, impact publication race, outbox restart and stale cell rejection. Use independent expected outcomes/reference scheduling fixtures, not tests that simply repeat the implementation's own decision method. Model contract tests inject hostile arguments and text even when no live model exists.
