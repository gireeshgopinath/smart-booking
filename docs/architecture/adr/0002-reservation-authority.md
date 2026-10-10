# ADR 0002: PostgreSQL reservation authority and atomic moves

Date: 10 October 2026. Status: adopted design baseline; real PostgreSQL tests pending.

Availability caches are advisory. Active holds and confirmed exclusive allocations share a bounded `[)` range exclusion constraint; capacity uses locked conditional count updates and allocation records. Use tenant-aware keys, transaction-local RLS context, nonowner runtime roles and stable fence/guard/resource/occurrence/aggregate locking.

A tenant scheduling guard advances on inventory/config/external-busy changes. It gives initial implementation a simple protection against scheduler/publication races and stale impact reports. Later lock splitting needs proof against phantoms and deadlocks.

Reschedule proposals are advisory until client-approved atomic commit. An independent target hold can conflict with the same guest's existing partially overlapping booking. The transaction locks the complete old/new resource set, defers only its named exclusion constraint when needed, performs the full swap, checks final constraints and commits once. Any failure retains original booking and allocation. No cross-cell move is admitted.

Idempotency persists canonical request hash and terminal outcome with the same transaction; bounded concurrent duplicate requests do not execute independent mutations. Known domain rejections use a tested savepoint/result strategy. Authoritative deadline time is sampled after locks; stopped expiry workers cannot legalize expired confirmation.

Consequences: target availability can disappear before move commit, which yields a visible conflict while preserving the original. Constraint deferral requires targeted overlapping-move/other-guest concurrency tests. Redis locks, preflight counts and a separate cancel-then-book flow do not satisfy the invariant.
