# GlobalSema pending dependencies

## Purpose

Find and remove expensive, repeated pending-resolution work during one clean
compilation. Keep dependency and ready-queue state transient in GlobalSema;
`ModuleSemanticGraph` and `GlobalSemanticGraph` remain the semantic data.
This is distinct from persistent cross-build invalidation and ModuleSG caching
in [frontend_file_artifacts.md](frontend_file_artifacts.md).

Zig's explicit semantic dependencies and reduced over-analysis are useful
design references, but its incremental invalidation is not a drop-in model for
Argi's unresolved operations within one compilation. See the
[Zig 0.16 release notes](https://ziglang.org/download/0.16.0/release-notes.html#Incremental-Compilation).

## Current facts

- `PendingWorklists` routes each operation once to one of five phases and
  retains only unresolved or invalid work. Reachability can leave inactive
  operations dormant until a function becomes reachable.
- `resolvePendingPhase` retries each active `.deferred` operation on the next
  fixed-point round. The result has no recorded reason for deferral.
  `.invalid` is retained for later diagnostics and must not be treated as
  completed work.
- Type and binding resolution is reconciled after direct writes to graph
  slots. A wakeup design cannot assume one centralized setter exists today.
- In 16 pinned ReleaseFast runs of the current collections cases, the largest
  full-pool sweep was about 0.13–0.17 ms; generic type sweeping was about
  0.05–0.06 ms. A previous worklist prototype for error reasons had mixed
  results. These measurements do not justify converting sweeps wholesale.
- Aggregate pending time, attempts and rounds are available under `--stats`,
  but not time or retries by operation kind. No evidence yet shows that
  repeated waits on the same type or binding dominate pending time.

## Hypotheses to test

1. A small set of expensive pending operations, especially calls, accounts
   for most pending time through repeated `.deferred` attempts.
2. Many of those attempts encounter the same unresolved type or binding and
   could sleep until that specific prerequisite changes.
3. Some time attributed to pending calls is spent in repeated ordinary,
   abstract-compatible and generic matching. Destructor lookup may repeat
   equivalent dispatch questions or create graph objects on failed probes.
4. Other deferrals depend on candidate availability, visibility, generic
   specialization, abstract conformance or reachability. A two-kind
   type/binding dependency model may cover only a minority of costly retries.

Do not implement a dependency queue merely because attempts per operation are
high. First establish which repeated attempts are expensive and have a
reliable, observable prerequisite.

## Experiments and decision points

### 1. Profile pending work without changing resolution

- [ ] Under `--stats`, count initial operations, attempts, resolved, invalid,
      deferred attempts and elapsed time by `PendingOwner` and operation tag.
      Report attempts per operation and time per attempt. Keep timing
      overhead opt-in and avoid summing nested timings as independent costs.
- [ ] For costly call and ownership paths, split ordinary matching,
      abstract-compatible matching, generic matching and reach completion.
      Count candidates and attempts where practical.
- [ ] In destructor lookup, count calls, distinct *query contexts* (target
      type plus module/visibility and relevant reach/input context), success,
      failed probes, graph nodes/fields/strings appended, and time spent in
      receiver discovery, input construction and dispatch. A repeated TypeId
      alone does not prove two lookups are equivalent.
- [ ] Benchmark `36_dynamic_array_owning_mutations`,
      `17_string_hash_map_baseline`, and `23_named_struct_auto_deinit` with
      alternating before/after ReleaseFast runs pinned to one CPU. Compare
      pending time, GlobalSema and indexed frontend as well as local counters.

Decision: identify a high-cost tag and a repeated prerequisite before changing
the scheduler. If time is instead in candidate matching or speculative graph
growth, optimize that operation directly.

### 2. Observe why work defers

- [ ] Add opt-in observations at the point a resolver discovers an unavailable
      prerequisite. Start with unresolved type and binding IDs; bucket all
      other reasons separately. Record whether a later attempt sees the same
      blocker, a new blocker, or no blocker.
- [ ] Inventory every write that can satisfy the chosen prerequisite,
      including direct slot writes, reconciliation, generic specialization,
      materialization, reachability expansion and ownership finalization.
      Identify the event that can be emitted *after* the value is usable.
- [ ] Audit speculative graph rollback and ID reuse. Dependency records must
      not retain IDs from a discarded candidate or wake an unrelated entity
      that later reuses an ID.

Decision: pilot sleepers only if repeated same-blocker retries account for a
meaningful share of pending time and every relevant wake event is covered.

### 3. Pilot one operation kind

- [ ] Select the measured costly tag. Keep its waiters in transient GlobalSema
      state, indexed by the specific type/binding prerequisite. Leave other
      tags on the current phased worklists.
- [ ] On `blocked(X)`, register the current work item once and remove it from
      ready work. On X becoming usable, enqueue the item once. A reawakened
      item may discover another prerequisite and sleep again.
- [ ] Preserve source order where it affects diagnostics or selection, and
      preserve `.invalid` items for the existing diagnostic pass. Handle
      reachability growth and new cleanup calls as explicit wake sources.
- [ ] During rollout, retain a bounded fallback retry at convergence and
      count fallback-only resolutions. Zero fallback-only successes on the
      relevant suite is required before removing that safety net.
- [ ] Compare graph output and diagnostics with the old scheduler, including
      forward calls, generic specialization, abstract dispatch, ownership,
      negative tests, and selective versus exhaustive semantizing. Run the
      full `zig build test` suite and paired performance measurements.

Decision: retain the pilot only if it improves end-to-end time beyond run
variance without changing resolution or diagnostics. Expand dependency kinds
one measured operation family at a time; do not build a general dependency
graph up front.

## Correctness constraints

- A ready queue becoming empty does not itself prove a dependency cycle:
  inactive, invalid, impossible and externally blocked work require the
  existing diagnostic distinctions.
- `Resolution.Result` has `not_applicable`, `deferred`, `invalid` and
  `resolved`. Composite owners try multiple strategies; a blocker found in
  one strategy must not prevent another strategy from resolving the operation.
- A dependency may be discovered in stages: waiting on A can reveal B only
  after A resolves. Stale registrations need deduplication or an attempt
  generation so wakeups do not multiply work.
- Registration and wakeup need to describe actual semantic changes. Scanning
  graph pool lengths is insufficient because existing type and binding slots
  can be filled without append.
- Keep this within-build mechanism separate from stable IDs and dependency
  invalidation across source edits. Persistent incremental semantics can reuse
  lessons from the pilot later, but need their own identity and cache policy.
