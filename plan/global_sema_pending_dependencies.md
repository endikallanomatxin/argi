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

- [x] Under `--stats`, count initial operations, attempts, resolved, invalid,
      deferred attempts and elapsed time by `PendingOwner` and operation tag.
      Report attempts per operation and time per attempt. Keep timing
      overhead opt-in and avoid summing nested timings as independent costs.
- [x] Split implicit-function lookup into ordinary,
      abstract-compatible, generic matching and reach completion time,
      calls and outcomes. Candidate counts inside the matching modules remain
      to be added only if one strategy needs deeper profiling.
- [ ] Classify distinct destructor *query contexts* (target type plus
      module/visibility and relevant reach/input context). A repeated TypeId
      alone does not prove two lookups are equivalent.
- [x] Count destructor successes, failures, repeated target TypeIds, appended
      graph objects and phase times. Distinct equivalent query contexts are
      still unknown.
- [x] Benchmark `36_dynamic_array_owning_mutations`,
      `17_string_hash_map_baseline`, and `23_named_struct_auto_deinit` with
      alternating before/after ReleaseFast runs pinned to one CPU. Compare
      pending time, GlobalSema and indexed frontend as well as local counters.

First profile findings (16 alternating paired ReleaseFast runs, CPU 0):

- In `17_string_hash_map_baseline`, `resolve_call` accounted for roughly 2.7
  ms of 3.1 ms median pending time. It had 257 initial operations, 117
  attempts, 52 deferred attempts and 65 resolutions in a representative run.
- Destructor resolution attempted 147 lookups: 8 succeeded and 139 failed.
  There were 128 repeat lookups by target TypeId; this does not establish
  equivalent lookup context. Failed lookups appended 417 nodes, 278 value
  fields and 7,719 string bytes in that run. Some appended objects may be
  side effects of nested resolution, so they cannot yet all be called waste.
- Implicit generic matching is the largest measured destructor substage.
  The added detailed timers increased median `StringHashMap` frontend time
  by about 2.9% under `--stats`; keep comparative builds equally instrumented.

Second profile findings (24 ReleaseFast runs pinned to CPU 0, with the same
instrumented compiler in each run):

| Case | Median pending | Median call resolution | Deferred-call time | Deferred call attempts |
| --- | ---: | ---: | ---: | ---: |
| Dynamic array owning mutations | 1.58 ms | 1.14 ms | 0.16 ms | 45 |
| String hash map | 3.07 ms | 2.68 ms | 0.27 ms | 52 |
| Named struct auto deinit | 0.36 ms | 0.18 ms | 0.02 ms | 8 |

The sampled call gates in Core observed no unresolved TypeId or BindingId in
these deferred attempts. This does not classify deferrals inside generic,
abstract, constructor or control strategies. Even eliminating *all* deferred
call attempts would save at most the deferred-call time shown above; successful
call resolution accounts for most measured pending time. The dependency-queue
pilot is therefore **not justified by the current workloads**.

The `ready_queue` / `remaining_deps[WorkId]` /
`dependents[DependencyId] -> WorkId[]` design remains a candidate if later
workloads show costly repeated blockers. Dynamically discovered dependencies
need care: a counter can cover only dependencies already known, and a resumed
operation may reveal another. Deduplication, changing prerequisites, direct
slot writes, speculative rollback and reachability must be addressed before
sleeping work is authoritative.

Decision: identify a high-cost tag and a repeated prerequisite before changing
the scheduler. If time is instead in candidate matching or speculative graph
growth, optimize that operation directly.

### 2. Observe why work defers

- [x] Add opt-in observations at explicit Core call gates where a type or
      binding ID is unresolved. Preserve `flat_index` across attempts and
      count repeated single IDs without asserting that an observed ID caused
      the final deferred result.
- [ ] Extend observations only if a future workload shows expensive deferred
      calls with no blocker identified at the current gates. Additional
      resolver families may have other causes.
- [ ] Inventory every write that can satisfy the chosen prerequisite,
      including direct slot writes, reconciliation, generic specialization,
      materialization, reachability expansion and ownership finalization.
      Identify the event that can be emitted *after* the value is usable.
- [ ] Audit speculative graph rollback and ID reuse. Dependency records must
      not retain IDs from a discarded candidate or wake an unrelated entity
      that later reuses an ID.

Decision: do not pilot sleepers on the current benchmarks. Revisit only if
repeated same-blocker retries account for a meaningful share of pending time
and every relevant wake event is covered.

### 3. Pilot one operation kind

On hold: the phase 1–2 measurements above did not meet the decision gate.

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
