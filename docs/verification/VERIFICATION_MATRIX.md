# Application verification and traceability baseline

All application gates currently have status **NOT_RUN**. This pack reconstructs missing support documentation; it does not claim the original `10_VERIFICATION_AND_TRACEABILITY.md` or R01–R30 definitions were supplied. V01–V26 below retain the backend source semantics. A01–A20 are an adopted replacement derived from the master T27–T42 and Word design requirements, explicitly subject to refinement with preserved coverage.

## Retained backend gates

| Gate | Required observation | Main tasks | Readiness |
| --- | --- | --- | --- |
| V01 | Clean build and fresh/upgrade migrations pass | T01,T02,T05 | Mandatory local |
| V02 | Anonymous flow persists one booking and confirmed allocation | T08,T09 | Mandatory local |
| V03 | Second guest cannot read, approve or confirm another hold | T08,T09 | Mandatory local |
| V04 | At least 100 simultaneous exclusive-slot attempts yield at most one active allocation | T05,T09 | Mandatory local |
| V05 | More than N requests never reserve more than N seats, including holds | T10 | Mandatory local |
| V06 | Lost-response retry returns the same operation/booking | T09 | Mandatory local |
| V07 | API, SQL/RLS, pooled context, cache, exports and AI maintain tenant boundaries | T04,T05,T15,T17 | Mandatory local |
| V08 | DST gaps/overlaps, overnight and adjacent intervals give specified instants | T07 | Mandatory local |
| V09 | Expired hold cannot confirm with expiry worker stopped | T08,T12 | Mandatory local |
| V10 | Failed reschedule retains the original booking/allocation | T09 | Mandatory local |
| V11 | Restarted outbox relay delivers committed work without duplicated state | T11 | Mandatory local |
| V12 | Restarted Temporal worker resumes with legal single mutations | T12 | Mandatory local |
| V13 | All simulator scenarios, including late/duplicate/reordered/invalid signature, are legal | T13 | Mandatory local |
| V14 | No actual payment adapter/SDK/card field/financial credential/money operation | T13,T41 | Mandatory local |
| V15 | Prompt injection and forged approval cannot authorize mutation | T17,T18 | Mandatory local |
| V16 | Actual configured model searches, proposes and confirms only after client approval | T17,T35 | Separate live local model |
| V17 | Independent MCP/A2A clients prove discovery, approval wait, auth and actual result | T19,T35 | Mandatory local |
| V18 | Cell A outage leaves tested cell B booking available | T20 | Mandatory local |
| V19 | Migration rejects stale source writes; destination alone becomes authoritative | T20 | Mandatory local |
| V20 | Fresh Compose deployment supports booking and local inbox delivery | T22 | Mandatory local |
| V21 | Same images support actual booking through dedicated kind ingress | T23 | Mandatory local |
| V22 | Rollout/rollback preserves schema/data/workflow compatibility | T23,T25 | Mandatory local |
| V23 | Isolated restore reconciles counts, allocations, operations and jobs | T25,T40 | Mandatory local |
| V24 | Overload stays bounded and fair without false confirmation | T21,T25 | Mandatory local |
| V25 | Created logs/examples/traces/history contain no secrets or guest capabilities | T21,T41 | Mandatory local |
| V26 | Final evidence/commands match final tested source and images | T26,T41,T42 | Mandatory local |

## Reconstructed whole-application gates

| Gate | Required observation | Main tasks | Readiness |
| --- | --- | --- | --- |
| A01 | Guest and staff apps render; typed client rejects incompatible/error responses; private data absent from public bundle | T27 | Mandatory local |
| A02 | Owner and restricted staff portal journeys pass; direct forbidden API call fails | T28 | Mandatory local |
| A03 | Fresh anonymous browser completes live selection, contact, exact review, approval, booking and local email | T29 | Mandatory local |
| A04 | Management fragment exchange clears token; cancellation/move/recovery and lost-response lookup work without account | T29 | Mandatory local |
| A05 | Keyboard, labels, focus, errors, contrast, reduced motion and 360px guest/staff journeys pass declared accessibility checks | T30 | Mandatory local |
| A06 | English and second test language format dates/money with explicit location zone; no ambiguous implicit booking date | T30,T35 | Mandatory local |
| A07 | Blueprint schema/reference/provenance validation rejects unresolved material fields and unsafe code before publish | T31 | Mandatory local |
| A08 | Shared scheduler rehearses isolated synthetic scenarios; no real messages or reservations created | T32 | Mandatory local |
| A09 | Impact hash/version/revision expires and a concurrent conflicting booking invalidates old approval; publication is atomic | T32,T33 | Mandatory local |
| A10 | Builder UI shows facts, clarification, diff, trusted preview, rehearsal, impact and exact owner approval; rollback revalidates | T33 | Mandatory local |
| A11 | Connector permission/mapping preview, encrypted token references, test/health/revoke and SSRF rejection work | T34 | Mandatory local |
| A12 | Calendar contract clients handle duplicates, resync, revoke, throttle and echo loops; conflicts remain visible | T14,T34 | Mandatory local contracts; live accounts separate |
| A13 | Optional intent UI uses actual slots, material clarification, cancel/status recovery and manual fallback; cannot self-approve | T35 | Mandatory local contracts; live model separate |
| A14 | Portable salon/class/rental drafts import with logical references and no credentials/customer data; recipes require bounded typed actions | T36 | Mandatory local |
| A15 | Absence/recovery options preserve appointments until staff/guest approvals; expiry, consent and FIFO waitlist rules apply | T37 | Mandatory local |
| A16 | Insight numbers reconcile; source/period visible; opted-out funnel data excludes raw contact; advice cannot mutate rules | T38 | Mandatory local |
| A17 | P3 flags off; multi-stage failure rolls back; voice/message intents cannot confirm; advice backtest limitations recorded | T39 | Mandatory prototype contracts; live media NOT_RUN |
| A18 | Compose and kind run guest/business/builder journeys with correct cookie/CORS/TLS policy and compatible frontend/API upgrades | T40 | Mandatory local |
| A19 | Full-app measured load/restore and cloud-template validation recorded; external deployment/scale claims kept separate | T40 | Mandatory bounded local; larger scale/cloud separate |
| A20 | Final tested source, statuses and release report reconcile; existing startup/deployment/restore instructions reproduce the declared local release | T41 | Mandatory local release precheck |

## Baseline requirement mapping

The B identifiers are new preparation-pack labels. Source task references to R01–R30 remain preserved in `contracts/tasks.json` for future reconciliation; their missing definitions are not invented.

| Baseline requirement | Source meaning | Tasks | Gates |
| --- | --- | --- | --- |
| B01 | Account-free guest lifecycle and management | T08,T09,T29 | V02,V03,V06,V09,V10,A03,A04 |
| B02 | Business identities, roles and configuration | T04,T06,T28 | V07,A02 |
| B03 | Correct exclusive/capacity scheduling | T05,T07,T10 | V04,V05,V08,V09 |
| B04 | Durable events, reminders and workflows | T11,T12 | V11,V12 |
| B05 | Simulator-only payments | T13,T29,T41 | V13,V14 |
| B06 | Authorized bounded AI tools and intent UI | T16–T19,T35 | V15,V16,V17,A13 |
| B07 | Safe blueprint construction and publication | T31–T33 | A07–A10 |
| B08 | Private connectors and calendar contracts | T14,T34 | A11,A12 |
| B09 | Templates, recovery and insights | T15,T18,T36–T38 | A14–A16 |
| B10 | Accessible localized guest/staff UI | T27–T30 | A01–A06 |
| B11 | Cell routing, fencing and bounded operations | T20,T21,T25 | V18,V19,V24 |
| B12 | Reproducible deployments, restore and evidence | T01,T22–T26,T40–T42 | V01,V20–V26,A18–A20 |
| B13 | Experimental contracts separately flagged | T39 | A17 |
| B14 | Secrets, consent and tenant privacy | T04,T05,T15,T17,T21,T30,T34,T38,T41 | V07,V15,V25,A04,A11,A16 |

## Recording and aggregate result

Each gate records status PASS/FAIL/BLOCKED/NOT_RUN, exact command/exit code, time/zone, tested revision/image digests, environment, synthetic dataset, expected/observed behavior and evidence paths. A task's gate list is necessary coverage, not a replacement for its full packet acceptance criteria.

T42 adds the final handoff gate **H01**: completed operator/developer handbook, owner pilot walkthrough and actual recorded owner acceptance. H01 follows T41; it is deliberately separate from A20 so T41 verification does not depend on its own successor. T41 may pass release verification while H01 and whole-project handoff readiness remain pending. The application development goal still requires both.

The future `make verify-release` must take a declared scope: `SCOPE=backend` at T26 covers V01–V26 and retained backend criteria; `SCOPE=application` at T41 additionally covers A01–A20 and full application criteria. A reviewed cross-platform wrapper must expose equivalent scope semantics. This prevents T26 from requiring frontend tasks that follow it. Neither scope treats separate live-provider/large-scale validation as a false local PASS, and an absent mandatory local check fails its scope.

Mandatory local FAIL, BLOCKED or NOT_RUN means incomplete local readiness and a nonzero final verifier result. V16, live calendar/SMTP accounts, paid cloud deployment and representative scale runs remain independent labels; a deterministic provider is not live inference. Local-model development capability is also separate from product V16. Report P3 implementation and live-media status separately. The cloud template gate validates assets without provisioning paid infrastructure. Do not hide unavailable mandatory tests in an aggregate PASS.
