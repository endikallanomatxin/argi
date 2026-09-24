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
- `--stats` now reports pending time and outcomes by owner and operation kind.
  Deferred call attempts are a small part of measured pending time; the Core
  gates sampled so far found no repeated unresolved type or binding ID.

## Three-way regression baseline (2026-09-24)

Measured `3e3802b9` (before compact semantic graph), `6f80ed92` (immediately
after), and `bbb5aa2a` (current at measurement). Each compiler was built in
ReleaseFast with Zig 0.16.0 and LLVM 21. All compiled the unchanged test
programs below against the same current `core/` through `ARGI_SYSROOT`.
Results are medians of 24 alternating runs per case, pinned to CPU 0, with
`--stats` and the target's default development optimization mode.

| Case | Frontend before | Frontend after | Frontend current | Current vs before |
| --- | ---: | ---: | ---: | ---: |
| Dynamic array owning mutations | 8.96 ms | 48.65 ms | 12.61 ms | +41% |
| String hash map baseline | 11.07 ms | 91.58 ms | 17.17 ms | +55% |
| Named struct auto deinit | 8.21 ms | 20.74 ms | 8.53 ms | +4% |

The current frontend is 74%, 81%, and 59% faster than immediately after the
refactor, respectively. It still has a material regression in both collection
cases. The old compiler reports file collection, tokenizing, syntaxing and
semantizing separately; their sum is the comparable frontend number above.
Old semantizing and the new ModuleSema/GlobalSema split do not have identical
boundaries, so compare the complete frontend across all three revisions.

| Case | Codegen before | Codegen current | Frontend + codegen before | Frontend + codegen current |
| --- | ---: | ---: | ---: | ---: |
| Dynamic array owning mutations | 5.07 ms | 1.41 ms | 14.03 ms | 14.02 ms |
| String hash map baseline | 5.92 ms | 2.03 ms | 16.98 ms | 19.19 ms |
| Named struct auto deinit | 4.04 ms | 0.32 ms | 12.25 ms | 8.86 ms |

Codegen gains offset the frontend regression for dynamic array, but string
hash map remains about 13% slower before linking. Ownership is about 28%
faster before linking. Link time was similar across revisions and is excluded
from these sums. The detail and overhead of `--stats` changed between commits;
these are phase-timing comparisons, not a cycle-exact attribution of the
remaining regression.

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

The first direct lookup change moves an existing conclusive nominal `deinit`
receiver check before generic input inference. Across 24 alternating
ReleaseFast paired builds pinned to CPU 0, median generic matching fell 4.4%
for dynamic array owning mutations and 2.4% for string hash map; their
indexed frontend times fell 1.1% and 0.7%, respectively. Continue inspecting
the generic no-match path and query equivalence before introducing a cache.

The next generic no-match experiment moved the nominal check ahead of
candidate binding allocation. It did not improve indexed frontend time in 24
alternating ReleaseFast pairs (string hash map +0.1%, dynamic array -0.4%),
so it was discarded. Reusing the temporary inference bindings across
candidates in one implicit generic lookup was more effective: in 32 alternating
ReleaseFast pairs pinned to CPU 0, median generic lookup fell 21.8% for string
hash map and 16.9% for dynamic array. Indexed frontend fell 1.6% and 0.9%,
respectively. The ownership case's generic lookup fell 11.2% across 24 pairs,
but its 0.5% frontend increase is within the observed noise. All three builds
compiled the same test programs against the same core; the paired baseline was
`dea4c217`.

A negative cache for the entire destructor query needs module visibility,
target type, receiver name, reach context and invalidation on type/binding
resolution and newly instantiated functions. A negative answer can become
positive later in the fixed point. A broad ownership-side structural
prefilter is also deferred: ordinary, abstract and parameterized candidates
do not share a proven local compatibility predicate. Keep the existing
per-candidate nominal rejection until that predicate can be specified and
tested against all valid destructor forms.

The destructor no-match audit found that broad tail rollback is unsafe:
`#reach` call completion can add owner fields and bindings before a later
default fails, leaving durable references into those pools. A narrower change
delays writing generic arguments and their names until a candidate becomes
the current best match. In 32 alternating ReleaseFast pairs pinned to CPU 0
against `f3dd97ec`, failed destructor probes appended 36.7% fewer string bytes
in string hash map and 52.3% fewer in dynamic array; GlobalSemanticGraph
storage fell 0.7% and 0.4%. Indexed frontend changed by -0.8% and +0.3%,
respectively, so this is a graph-size improvement, not an established runtime
win. The same change passed the full compiler test suite.

The abstract-compatible ordinary matcher still scanned the entire function
pool after Core's indexed lookup had failed. Reusing `functionsNamed` cut its
median matching time by 57% in string hash map and 59% in dynamic array; across
32 alternating ReleaseFast pairs pinned to CPU 0, indexed frontend fell 1.3%
and 0.5%, respectively. This is a small but repeatable removal of an accidental
global scan and does not change abstract matching rules.

A conservative nominal receiver filter in destructor name collection was
tested and discarded. In the same three workloads it removed no destructor
dispatches or speculative nodes: generic/unknown receiver patterns kept the
same names visible. Across 32 paired runs it added roughly 0.2–0.6% frontend
time. Filtering names is ineffective while broad candidate patterns share a
receiver name; a future change must filter candidates within dispatch or
separate lookup from completion.

Source-call profiling (24 pinned ReleaseFast runs, `--stats`) shows that the
generic strategy dominates successful pending calls. In string hash map,
`resolve_call` took 2.52 ms median, of which generic strategy took 1.95 ms;
generic candidate selection took 1.93 ms and input completion 0.013 ms. In
dynamic array the corresponding values were 1.10, 0.75, 0.74 and 0.005 ms.
Across all paths, generic instantiation took 4.39 ms in string hash map
(85 invocations, 44 returning an existing instance), with body lowering
accounting for 3.81 ms and existing-instance lookup for 0.008 ms. These are
nested timings: instantiation occurs during source calls and other GlobalSema
work, so its total must not be added to pending resolution. Prioritize avoiding
unnecessary body instantiation or making the body lowerer cheaper; indexing
existing generic instances is unlikely to move these workloads.
Further timing of instance setup found only 0.12 ms for allocating/clearing
the three whole-module ID maps in string hash map (0.05 ms in dynamic array).
The body conversion itself remains about 3.9 and 0.75 ms, respectively, so
changing map allocation alone has a small maximum payoff. Inspect work done
per instantiated body node and whether each body is needed before changing
the map representation.

The next body experiment found no reachability waste in the normal build of
string hash map: 52 generic bodies were constructed and all 52 were reachable
at the end of GlobalSema. The `check` command requests exhaustive bodies, so
reachability-based delay would not help its current contract either. Reserving
the temporary node-reference list to the full block length was tested in 32
alternating ReleaseFast pairs against `24deaa04`; median body-lowering time
was unchanged (3.84 to 3.85 ms in string hash map), while frontend shifted
up 0.7–0.9% across the measured cases. The allocation change was discarded.
The remaining body cost needs a per-node breakdown before choosing a rewrite.

An ordered type-reference lookup in ModuleSema was also tested and removed.
Sorting each file's reference slice plus binary search did not consistently
improve ModuleSema or complete frontend across 32 paired ReleaseFast runs.

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
