# Measuring compiler frontend performance

Build the compiler and benchmark tool before measuring, with no test suite active:

```sh
zig build -Doptimize=ReleaseSafe install build-frontend-benchmark -j16
zig build -Doptimize=ReleaseSafe benchmark-frontend -- MODULE 12 1
zig build -Doptimize=ReleaseSafe benchmark-frontend -- MODULE 12 8
```

The optional arguments after the module select iteration and frontend worker
counts. The benchmark compares fresh and reused in-memory frontend work and edits;
source collection, LLVM code generation, and native linking are outside its timings.
Use the same sources, target, optimization mode, and machine load when comparing.

CLI builds persist canonical module snapshots in `.argi-cache/frontend/`.
`--no-cache` bypasses this reuse; `--stats` reports reuse. Global semantics, safety,
and code generation still run. Measure complete CLI builds separately from the
in-memory frontend benchmark.

The cache build identity follows literal Zig imports from `src/main.zig` and
hashes embedded files as data. It also includes `build.zig`, the fingerprint
implementation and the LLVM bridge header. Unreachable source files do not affect
that identity; imported files remain included regardless of their names, even
when the import appears in a test declaration. Computed dependency paths fail
explicitly instead of being omitted. Paths are normalized relative to the
checkout, and traversal scratch is released after each parsed file.

## Frontend workers

`--frontend-jobs auto` uses half the detected logical CPU count, rounded down,
with a minimum of one and a maximum of eight. CPU-query failure selects one.
Explicit counts from 1 to 256 override this policy. CPU detection is not a global
scheduler and does not guarantee detection of CPU quotas.

Only independent module discovery and local semantic lowering use these workers.
Parsing, cache acquisition/publication, global semantics, safety, and codegen stay
serial. Cache hits create no worker task; zero or one dirty module runs serially.
Worker count does not affect cache identity or language behavior.

Use `--frontend-jobs 1` when an outer runner schedules many compiler processes.
Program fixtures and `argi test` already select one frontend worker; dedicated
concurrency tests explicitly override it. Frontend workers and the regression
suite's `-Dtest-jobs` process workers are separate controls.

When changing concurrency, compare graphs, diagnostics, emitted LLVM, and program
results between serial and parallel runs. Include failing modules, cache reuse,
and worker cleanup. See [compiler testing](../CONTRIBUTING.md#compiler-tests).

## Incremental resolution profile

Build `zig build build-execution-benchmark -j2` with no active test suite, then run:

```sh
./zig-out/bin/execution-benchmark 1000 minimal calls 1024 --resolution-profile
./zig-out/bin/execution-benchmark 1000 minimal rejections 1024 --resolution-profile
./zig-out/bin/execution-benchmark 100 prelude calls 1024 --resolution-profile
```

The optional `# resolution` rows report cumulative pass calls, outer pool entries
visited, passes returning a change, inclusive milliseconds and fixed-point rounds.
Nested type/effect traversals are not counted as extra pool visits. Timings can
nest: global verification is inside completion, and materialization can recurse.
Do not add inclusive columns to estimate total time. Counters live outside semantic
transactions so rejected/speculative work remains visible. Normal compilation has
no profile collector. Use unprofiled runs for throughput comparisons.

Debug observations on Linux x86-64, based on `develop` `9a2cb9f1` plus this
instrumentation, with a 1,024 MiB tracked allocation limit:

| Session | Commands | Frontend/publication ms | Six pool passes ms | Global verification ms | Pending checkpoint ms |
|---|---:|---:|---:|---:|---:|
| Minimal / calls | 10 | 43.2 | 0.7 | 0.3 | 0.05 |
| Minimal / calls | 100 | 462.4 | 32.8 | 21.0 | 0.31 |
| Minimal / calls | 1,000 | 23,303.6 | 2,752.0 | 9,447.7 | 3.00 |
| Minimal / rejections | 1,000 | 2,432.9 | 23.7 | 0 | 2.56 |
| Prelude / calls | 100 | 22,850.3 | 3,275.7 | 984.4 | 37.72 |

The six passes cover binding types, assignment values, dereferences, addresses,
generic types and error-reason candidates. The 1,000 accepted minimal calls visit
33,673,566 outer entries across these passes without any of them returning a
change. Their 1,000 checkpoints copy just one pending entry in total; the prelude
case copies 622,201 entries across 100 checkpoints. Queue copying is not the main
cost in either measured workload.

Global verification is a stronger candidate in growing minimal sessions than
these six scans alone. Core/prelude sessions have a different cost distribution:
completion takes 11.38 s, resolution 7.20 s and checking 1.50 s across 100 commands.
These are diagnostic observations, not attribution to individual inner routines.
Profile verification components and remaining completion work before changing
validation boundaries or introducing new caches.

### Ordered module ownership lookup

`moduleForDeclaration` now searches the existing ordered physical declaration
ranges with binary search. It allocates no index and does not canonicalize source
fragments into their namespace owners. Graph partition validation still runs
before verifier symbol checks; no verification is skipped or cached.

A same-session Debug comparison on Linux x86-64, rebuilding the benchmark with
only that lookup changed (same profile instrumentation and workloads):

| Workload | Linear lookup total ms | Binary lookup total ms | Linear global verification ms | Binary global verification ms |
|---|---:|---:|---:|---:|
| 1,000 minimal calls | 25,529 | 17,090 | 9,839 | 1,163 |
| 100 prelude calls | 29,110 | 30,190 | 952 | 906 |

The minimal workload's total falls about 33%, and its global verification about
88%. Retained memory, pool visits, completed bodies and reuse counters are
unchanged. The prelude workload shows no end-to-end improvement in these single
runs; its verification cost is a small part of the total. Do not extrapolate the
minimal-session speedup to core-heavy programs. Raw run logs are local under
`.zig-cache/module-lookup-{baseline-,}{minimal,prelude}-calls.csv`.

Next investigate the remaining resolution/completion work in core-heavy sessions
and the other accumulated verifier traversals. This change addresses repeated
linear module ownership searches, not general incremental verification.

### Constraint validation without unused substitutions

The optional resolution profile also separates generic function/type constraints,
participant conformance validation, virtual registry closure and choice annotations.
In a Debug run of 100 calls with the prelude, generic function constraint checking
used 1,682 ms. Skipping substitution-environment allocation for signatures with no
constraints reduced that phase to 391 ms in a subsequent run. Constrained signatures
still bind arguments and check every constraint; no validated-state cache is added.
These are individual instrumented observations, not a cross-platform throughput claim.
The allocation-failure regression proves unconstrained functions/types can be checked
without allocating substitutions. Rejection and late-specialization fixtures retain
coverage of constrained functions and later evidence.

### Diagnose relevant node kinds before testing reachability

Completion profiling now separates input and value diagnostics. In a Debug
100-call prelude session these groups initially took 5,190 ms and 2,925 ms.
Filtering by the diagnostic's node kinds before consulting the selected-unit hash
set reduced value diagnostics to 668 ms in a subsequent run. The contract/runtime
binding check also now rejects ordinary types before searching every function's
input/output bindings for the interface exception. With both changes, the groups
measured 423 ms and 792 ms respectively. Graph iteration and diagnostic order stay
unchanged; every relevant selected node still receives the same checks. No state,
cache, or validation exemption is added. The observations are individual Debug
runs, not stable throughput guarantees.

The first array-diagnostic filter accidentally omitted standalone typed record
and array literals. Those node kinds are restored. A direct regression fails with
the incomplete filter and checks selected literals without declarations or
assignments, recursive dimensions and corrected valid values. Repeating the
100-call prelude measurement with that fix gives 536 ms for input diagnostics and
658 ms for value diagnostics. Earlier prefilter timings are historical observations,
not evidence that the incomplete filter preserved validation coverage.

Keep the distinction between candidate filtering and validation caching: the
former removes work that cannot affect a result, while the latter would need
explicit dependencies and rollback rules.

### Temporary reachability marks

The resolution profile now also times pending operations, published bodies,
text-literal and field-access types, error result refresh, propagated reached
inputs and reachability expansion. The additional entries report timings and
change counts; their pool-visit counters remain zero unless explicitly counted.

Reachability expansion accounted for 2,095 ms of 7,306 ms of resolution in a
Debug 100-call prelude session. Each traversal rebuilt two temporary hash tables
for visited function/node IDs. Those IDs index fixed pools while the traversal
borrows the graph read-only, so temporary bitsets replace the hash tables. The
retained executable selections remain sparse maps. Fresh marks on every traversal
preserve late body completion, newly resolved calls and recursive dependencies;
no cross-command cache or rollback state is added.

The baseline is `develop` `78aaaa9f` plus the expanded profile counters; the
comparison changes only the temporary traversal marks.

For comparisons, keep both benchmark executables in the same directory and use
the same core tree: executable-relative installed core takes precedence over the
development fallback. The paired runs below use binaries in `.zig-cache/`, so
both load the repository core. These are individual profiled Debug runs, not a
statistical throughput comparison. The retained graph and fixed-point rounds
must agree before attributing timing differences to traversal changes.

| Session | Commands | Reachability before ms | After ms | Frontend/publication before ms | After ms | Retained MiB, both |
|---|---:|---:|---:|---:|---:|---:|
| Prelude | 10 | 202.8 | 103.2 | 1,362.0 | 1,406.1 | 100.755 |
| Prelude | 100 | 2,094.6 | 981.5 | 14,264.5 | 13,450.2 | 102.133 |
| Prelude | 1,000 | 22,873.3 | 10,914.3 | 159,717.4 | 143,177.2 | 119.032 |
| Minimal | 10 | 10.8 | 6.6 | 47.9 | 37.7 | 0.237 |
| Minimal | 100 | 106.8 | 62.6 | 490.2 | 351.0 | 1.732 |
| Minimal | 1,000 | 2,467.2 | 1,916.7 | 13,124.0 | 11,354.8 | 18.107 |

Pass calls, pool visits, fixed-point rounds, compiled bodies/instructions and
Safety reuse counters agree across each pair. Retained memory is identical;
1,000-command tracked peaks are 119.373/119.375 MiB for prelude and
18.123/18.125 MiB for minimal. The prelude startup peak is slightly higher with
bitsets (103.815/104.305 MiB); dense marks cover whole pools even in sparse
traversals. Reachability improves consistently in these samples, while other
phase timings vary, including slower frontend/publication at ten prelude calls.
Do not interpret the aggregate differences as an isolated traversal speedup.

Logs: `.zig-cache/frontend-{before,after}-visits-minimal-1000.csv`,
`.zig-cache/frontend-before-visits-prelude-1000.csv` and
`.zig-cache/frontend-after-visits-source-prelude-1000.csv`. These cover the
10/100/1,000 milestones in one cumulative session per workload and revision.

### Pending generic representations within resolution

Generic materialization now distinguishes a completed representation from one
that is still pending (including a deferred compile-time evaluation or a defining
module not yet available). During one `advanceResolution` call, a local worklist
retains generic candidates and old unresolved type slots, discovers appended
types, and retires completed candidates. It does not survive the resolution call
or add checkpoint state. Setup retains its allocation-free full scan. Binding
and expression type propagation, the outer fixed point and final graph
verification are unchanged.

Paired profiled Debug runs against `e2832c63`, using binaries in `.zig-cache/`
and the same repository core:

| Workload | Commands | Generic visits before | After | Generic ms before | After |
|---|---:|---:|---:|---:|---:|
| Prelude calls | 10 | 181,440 | 93,376 | 70.4 | 42.4 |
| Prelude calls | 100 | 1,792,620 | 942,346 | 666.1 | 397.3 |
| Minimal calls | 100 | 22,205 | 11,099 | 1.36 | 0.89 |
| Minimal calls | 1,000 | 2,022,005 | 1,010,999 | 105.1 | 57.6 |

Visits now count initial discovery plus candidate attempts, rather than full-pool
visits on every round. Retained graph, bytecode, Safety counters, memory and
fixed-point rounds agree. Frontend/publication for 100 prelude calls was
14,314/13,766 ms; for 1,000 minimal calls it was 14,068/14,115 ms. This is a
localized improvement, not a demonstrated overall throughput gain. An earlier
baseline measured 557 ms for the prelude generic pass, illustrating run variation.
Logs: `.zig-cache/generic-pending-{repeat-before,status}-prelude-100.csv` and
`.zig-cache/generic-pending-{before,status}-minimal-1000.csv`.

### Binding inference and expression propagation

The binding-type profile now separates `binding_initializers` from
`expression_types`. Their visits sum to the existing `binding_types` counter;
its time includes both. Initializers are still inferred before the expression
sweep, and expressions retain node order. Already typed expressions are revisited
because later contextualization can change operand types. Independently typed
record literals, binding initializers and writes share one completion rule.
Nested lists are retried when their operands become compatible, even if their
parent record already has its nominal type; complete values stop reporting
changes. The assignment sweep follows expression propagation for this reason.

Arithmetic propagation skips coercion and representation queries when both
operands and the result already carry the same resolved type ID. A later operand
type change takes the ordinary path again. No worklist or completion cache is
introduced for expressions.

ReleaseSafe observations at `b2c450bd0` on Linux x86-64, using the installed
core from the same checkout and a 1,024 MiB tracked allocation limit:

| Session | Total ms at 10 / 100 / 1,000 commands | Retained MiB at 1,000 |
|---|---:|---:|
| Minimal calls | 4.7 / 43.5 / 499.1 | 16.194 |
| Prelude calls | 60.6 / 605.3 / 6,941.3 | 167.735 |
| Minimal bindings | 1.5 / 19.5 / 909.1 | 14.258 |
| Prelude bindings | 70.1 / 720.5 / 8,626.5 | 165.784 |
| Prelude rejections | 53.0 / 512.2 / 5,547.5 | 151.456 |

These are single profiled runs, not a before/after throughput comparison. Startup
and teardown are outside command timings. The rejected session retains 151.456
MiB at all three milestones, has no published units and passes the benchmark's
state-rollback and teardown-leak checks.

Across 1,000 prelude calls, binding initializers cost 22.2 ms, expression
propagation 284.2 ms and assignment contextualization 407.9 ms. Initializers
visit 7.9 million entries without changes; they are nevertheless under 0.4% of
frontend/publication time. A new binding worklist is not justified by this run.
Expression and assignment work are stronger candidates, but their contextual
types can change after initial completion. Preserve that behavior when reducing
scans. Checkpointing costs 66.1 ms; full resolution costs 1,970.6 ms and completion
1,191.1 ms, including 318.9 ms of graph verification. Inclusive times overlap.

Growing live bindings have a different cost: in the minimal 1,000-binding run,
checking costs 402.4 ms, including 143.2 ms for continuation fork and 215.5 ms for
seal. Do not attribute that growth solely to semantic graph scans.

Fresh one-worker CLI `build --stats --no-cache` runs also examined type interning:
weighted regression reports 9.7 ms and 4.1 million candidates; word count reports
19.8 ms and 8.7 million. Nominal requests account for 7.1/12.5 ms respectively.
The candidate-by-tag counters classify the entries visited, not the requested
type. These observations identify repeated searches; they do not establish the
benefit of adding another persistent index. Reference interning must use identity
rather than callable compatibility, retaining internal signature defaults.

Logs: `.zig-cache/frontend-current-{minimal-calls,prelude-calls,minimal-bindings,prelude-bindings,prelude-rejections}-1000.csv`
and `.zig-cache/frontend-current-{regression,word-count}-stats.log`.

### Execution preparation and continuation publication

The optional profile also separates `session_layout`, `bytecode_initialization`,
`bytecode_lowering`, `bytecode_verification`, `vm_preparation`,
`continuation_fork`, `continuation_seal` and `semantic_publication`. These remain
`# resolution` rows for compatibility with the existing report. They are
inclusive boundary timings; do not add them to their parent timings.
Initialization includes cleanup metadata and lookup preparation, while lowering
measures instruction/descriptor generation. Verification and VM preparation are
separate. Fork precedes body checking; seal is inside checking. Publication
includes committing semantic proofs and releasing the checked candidate.

For 100 prelude calls before the cleanup-classification change, Debug measured
3,019 ms initializing lowering, 26 ms generating bytecode and 3,078 ms verifying
it. ReleaseSafe measured 187, 4 and 182 ms respectively. Both initialization and
verification independently classify cleanup-owning types. The cost attributed
to lowering was primarily preparation, rather than instruction generation.

Ownership classification now discovers structural child ranges once per call
and propagates only pending aggregate candidates, preserving discovery order,
nominal equivalence and reference boundaries. Without selected destructor seeds,
all ownership bits remain false. This scratch work belongs to one read-only
classification; there is no cross-unit cache. Verification still computes its
own classification rather than trusting lowering metadata.

Paired ReleaseSafe profiles, using the repository core and a 1,024 MiB tracked
allocation limit (`dfde6a60` plus boundary timers before the change):

| Session | Commands | Initialization before/after ms | Verification before/after ms |
|---|---:|---:|---:|
| Prelude calls | 100 | 186.5 / 111.8 | 182.3 / 122.6 |
| Prelude resources | 100 | 246.6 / 142.6 | 274.1 / 181.3 |
| Minimal calls | 1,000 | 21.4 / 4.3 | 43.5 / 28.6 |
| Minimal bindings | 1,000 | 122.7 / 93.7 | 39.1 / 19.5 |

Emitting bytecode for 100 prelude calls costs 4.1/4.3 ms. Graph/bytecode and Safety
reuse counters match, as do reported retained/peak memory. Rejected commands
publish no executable unit in either version. Retained memory is 102.133 MiB for
100 prelude calls, 145.689 MiB for 100 resource commands and 16.106 MiB for 1,000
minimal bindings; these are tracked allocations, not process RSS.

One profiled prelude run had a slower total despite faster preparation, due to
frontend variation. Separate unprofiled A/B/B/A runs (two samples per binary)
gave mean cumulative times of 1,994.6/1,866.1 ms for 100 prelude calls and
3,280.9/3,046.9 ms for 100 prelude resource commands. This is a local observation,
not a general throughput guarantee. Both saved executables reside in
`.zig-cache/` so core resolution and optimization modes agree.

Continuation copying depends strongly on live state. Before the change, fork
and seal together cost 7.4 ms for 100 prelude calls, but 853.7 ms for 1,000
minimal bindings (327.7 ms fork, 526.0 ms seal) out of 2,696.2 ms total. With the
cleanup change the latter remains 830.5 ms out of 2,555.0 ms. This warrants a
separate investigation of continuation facts and persistent session layouts;
it does not show that function-summary/body-proof caches should be merged.

Logs: `.zig-cache/execution-boundaries-{before,after}-release-*.csv` and
`.zig-cache/execution-throughput-{calls,resources}-*.csv`. Workloads include
prelude calls/resources/rejections and minimal calls/bindings. All report the
10/100 milestones, plus 1,000 for the minimal workloads. Initial core/prelude
preparation and reset/teardown are outside the cumulative command timings.

### Linear session-layout identity validation

`session_layout.build` previously searched every preceding binding for each row.
It now uses a temporary dense bitset keyed by validated global binding IDs. This
preserves duplicate rejection (including static bindings), source order and
cleanup selection; the bitset is not retained by executable units. Allocation
failure tests cover construction and both invalid/duplicate input paths.

Paired ReleaseSafe profiles with binaries in `.zig-cache/` and a 1,024 MiB limit:

| Session | Commands | Layout before/after ms | Total before/after ms |
|---|---:|---:|---:|
| Minimal bindings | 100 | 1.091 / 0.884 | See cumulative logs |
| Minimal bindings | 1,000 | 189.173 / 45.690 | 2,599.978 / 2,432.001 |
| Prelude resources | 100 | 8.038 / 6.576 | 3,279.656 / 3,080.639 |

These are individual instrumented runs, not statistical throughput estimates.
The resource total varies mainly outside layout construction. Retained and peak
tracked memory, compiled instructions and reuse counters match in paired runs:
16.106/18.012 MiB for 1,000 bindings and 145.689/147.826 MiB for 100 resources.
A 1,000-call control spends 1.681 ms in session layouts. The rejection control
publishes no units and retains 100.660 MiB after 100 commands.

The same reports distinguish retained frame identity metadata from slot backing.
After 1,000 minimal calls, 2,001 dead frame identities occupy 208,208 bytes, while
dead frame slots retain only 528 bytes. The 100-resource workload has 31,318 dead
identities (3,622,528 identity bytes) and 405,680 dead slot bytes. Those figures do
not justify changing identity lifetime or reclaiming storage through live
references without a more specific workload. Verification costs 21.677 ms for
1,000 bindings and 175.261 ms for 100 resources; join-state representation needs
a branch-heavy workload before any change. Continuation fork/seal remains the
larger binding-session cost and is a separate follow-up.

Logs: `.zig-cache/session-layout-{before,after}-{bindings-1000,resources-100}.csv`,
plus after-only calls and rejections controls. All command runs include the
10/100 milestones; minimal runs also include 1,000.

### Continuation publication and branch verification

A continuation candidate now retains its parent proof and forks the parent's
mutable tables directly into checking scratch. Previously it cloned those
tables into the candidate arena, then immediately cloned them again into
scratch and discarded the first copy. Publication still snapshots final facts
into an independent proof arena; rejecting a candidate still leaves its parent
unchanged. No historical chain or new persistent cache is introduced.

`continuation_fork` now times that actual checking fork. The earlier timer
covered the discarded candidate-arena copy while the second copy was included
only in `checking`. Compare cumulative command timings rather than interpreting
the boundary counters as two equivalent implementations of all copying work.

The `branches` execution scenario calls a reusable Argi function with 32 local
slots, 32 conditional writes and an outer branch. It reports ordinary reuse
counters and separately re-verifies the published unit at each milestone,
outside command timing. `# verifier` rows contain command count, cumulative
requested allocation bytes, peak live bytes and bytes retained after this
isolated verification. `--verifier` remains the synthetic linear/diamond
comparison; it is not a substitute for the Argi workload.

An attempted pointer-free bulk-copy path in fact snapshots did not improve the
measured 1,000-binding seal time (515.5 ms versus 510.2 ms in the prior profile).
That extra mechanism was discarded. Only the redundant whole-state fork was
removed.

A paired ReleaseSafe 1,000-binding run measured 2,368.0 ms before the fork change
and 2,023.8 ms after it, with frontend/publication falling from 2,167.2 to
1,814.8 ms. Retained memory remained 16.106 MiB; peak tracked allocations fell
from 18.012 to 17.377 MiB. This is one instrumented comparison, not a general
throughput guarantee. Both binaries use the repository core from `.zig-cache/`.
The 1,000-call control completed in 1,138.7 ms with 999 body reuses. Across 1,000
prelude rejections, retained allocations remained 100.660 MiB, with no published
bytecode or additional dead frames.

The real branch workload completed 1,000 calls with 999 body reuses. Re-verifying
its published unit requested 860,383 bytes cumulatively, peaked at 21,974 live
bytes, and retained zero bytes at every milestone. The synthetic 1,000-slot
comparison peaked at 25,289 bytes for linear code and 2,077,429 bytes for 1,000
diamonds; both retained zero. These results support keeping the current join
representation rather than adding another cache or persistent verifier state.

The default resource run reached its VM cell quota after 125 commands, retaining
146.625 MiB with a 149.660 MiB tracked peak. This was `ExecutionMemoryLimit`, not
an allocator failure or the benchmark's 1,024 MiB allocation limit. Investigation
found that transferring a reusable call buffer charged its slots and flags
again. Quota accounting now charges backing once and each fresh frame identity
once; session preflight uses the same rule. This changes no reference identity,
cleanup obligation or physical buffer lifetime. Tight-quota and allocation-failure
tests cover transfer, rejection and preservation of the reusable buffer.

Aggregate backing, rebuilt projections and immutable snapshots still belong to
the execution arena. Ending a call does not prove that these are unreachable:
results, session values and references can retain them. Reclaiming them requires
an explicit distinction between temporary and published backing, including
virtual descriptors and acquired storage, rather than resetting an invocation
arena or reusing dead frame IDs. That is a concrete follow-up, not a reason to
introduce reclamation into this change without lifetime evidence.

Logs: `.zig-cache/continuation-single-fork-*.csv`,
`.zig-cache/continuation-verifier-synthetic.csv`, and the focused
`.zig-cache/retained-call-quota-internal.log`. The attempted bulk-copy control is
`.zig-cache/continuation-bulk-only-bindings-1000.csv`.

After correcting buffer charges, the same default-quota resource scenario stops
after 478 commands, with 320.530 MiB retained and a 326.798 MiB tracked peak.
The 100-command milestone still retains 145.689 MiB: correcting quota accounting
is not physical memory reclamation. The default cell guard remains enabled; the
attempted 1,000-resource run is deliberately reported as quota-limited, rather
than as a completed throughput sample. Its bounded failure is recorded in
`.zig-cache/retained-call-quota-resources-1000.csv`.

Final unprofiled A/B/B/A 1,000-binding runs measured 2,368.5/2,242.7 ms before
and 1,851.5/1,944.1 ms after these changes (means 2,305.6/1,897.8 ms, about 18%
lower for this local workload). Logs are
`.zig-cache/retained-call-quota-throughput-{before,after}.csv`. The final prelude
call control completed 100 commands in 1,844.1 ms, retaining 102.133 MiB; the
1,000-branch control retained the same 21,974-byte isolated verifier peak and
zero verifier bytes after completion.

Validation: the full Debug internal suite passed 980 tests with one skip before
the quota correction. After that correction, 45 focused storage, acquisition,
quota and allocation-failure tests passed. The complete ReleaseSafe program
suite passed 2,362 tests with 11 optional skips, no failures and no leaks,
including the real-terminal editor, native/VM, compile-time, rejected-command,
reference, ownership and cleanup cases. Changed Zig files and the new aggregate
diagnostic fixture pass their official format checks. Logs:
`.zig-cache/overnight-final-{internal,programs}.log` and
`.zig-cache/retained-call-quota-internal.log`.

### Scoped execution scratch and resizable bookkeeping

The next investigation separated allocations by lifetime rather than introducing
a collector or a second ownership model:

| Data | Owner and recovery |
|---|---|
| Call input and nested-result envelopes | One reusable execution buffer; its live capacity is charged and released on exit |
| Captured write destinations | Active frame; freed on return or trap |
| Partial call cells and tables | Active frame; complete materialized values remain independently owned by the value arena |
| Frame/region identity pools and lookup indexes | Context owner's allocator; old resized backing and teardown allocations can be reclaimed |
| Public results, immutable aggregates, projections and virtual descriptors | Value arena; continue to survive until context reset |

IDs and their meanings do not change when pool backing moves. Dead frame IDs
remain dead; reusing buffers does not reuse identities or transfer cleanup flags.
The VM reserves its frame-stack capacity before constructing a frame, so failure
to append cannot strand separately allocated captures. Failure/trap paths retire
all active frames without running additional language cleanup.

An optional `AllocationProfile` observes payload requests and transfer traffic.
The execution benchmark prints `# transfers` (commands, call-input cells,
nested-result cells, write-destination entries), `# backing` (commands,
aggregate cells, partial cells, projection cells, virtual descriptor bytes), and
`# visible-backing` (commands, aggregate cells, projection cells, virtual bytes
observed from live frame values). Traffic includes subsequently freed backing.
The live-frame walk does not follow references, and its slice-based counts do
not identify whole allocations or externally retained invocation results. These
rows are diagnostics, not a proof that any specific buffer can be reclaimed.
The observer's scratch is outside session allocation accounting and command
execution timing.

A Debug 100-resource run attributed 69,614 call-input cells, 14,410 nested-result
cells and 6,804 write-destination entries. After scoping those allocations and
moving resizable bookkeeping out of the value arena, arena capacity fell from
44,564,726 to 6,802,606 bytes. Total tracked retained memory fell from 145.689 to
115.840 MiB (peak 147.682 to 117.107 MiB); the reduction is real, rather than only
moving allocations outside the arena counter. Compiled instructions, dead frame
count, live acquisitions, acquired bytes and body reuse counters matched.

The final diagnostic run requested 31,158 aggregate cells, 36,640 partial cells,
10,109 projection cells and 17,952 virtual descriptor bytes. Live-frame payload
inspection observed 5,719 aggregate cells, one projection cell and the same
17,952 virtual bytes. This motivates a later investigation of unused immutable
payloads, with explicit publication/escape rules rather than freeing them just
because a frame returns.

CLI VM execution now receives the command owner's allocator, and compile-time
execution receives the evaluator's supplied allocator rather than its local
lowering arena. Lowering/code metadata retain their own batch lifetime. Actual
physical recycling follows the allocator supplied by the owner; an embedder
that deliberately supplies an arena retains its usual arena behavior. There is
no hidden global-heap fallback, preserving allocation-failure injection.

Debug attribution logs:
`.zig-cache/runtime-transfers-{before,after}-resources-100.csv`.

Final ReleaseSafe runs used the same repository core, a 1,024 MiB tracked limit
and the default VM quotas. The 100-resource milestone reproduces the Debug
memory figures: 115.840 MiB retained and a 117.107 MiB peak, versus
145.689/147.682 MiB before. One thousand resources now complete rather than
stopping at the old 478-command quota boundary: 233.783 MiB retained,
251.384 MiB peak, 1,000 live acquisitions and 40,000 acquired bytes. No quota was
raised. The cumulative transfer counts are 696,014 input cells, 144,010 nested
output cells and 68,004 write-destination entries.

A 1,000-call control retains 16.273 MiB instead of 18.107 MiB. Its value arena
falls from 2,212,396 to 1,780 bytes, while 2,001 dead frame identities remain dead
and reuse counters match. One thousand binding commands retain 14.561 MiB;
one thousand prelude rejections remain at 100.611 MiB and publish no bytecode.

Short unprofiled A/B/B/A runs do not establish a general throughput gain:

| Workload | Before samples ms | After samples ms | Mean VM execution before/after ms |
|---|---:|---:|---:|
| 1,000 minimal calls | 1,317.4 / 1,325.3 | 1,331.5 / 1,242.1 | 9.27 / 8.17 |
| 100 prelude resources | 3,567.1 / 3,065.6 | 3,440.4 / 3,657.9 | 216.91 / 213.72 |

Resource total means increased about 7% in this small series, with substantial
frontend variation; VM execution means are close. Debug execution is slower
with individually freed bookkeeping because its backing allocator performs
additional checking. The demonstrated result is lower retained memory and a
larger useful workload within the existing quota, not an across-the-board speed
claim. The 1,000-resource run takes about 60.4 s, of which 52.3 s is frontend and
publication and 1.91 s is VM execution; frontend scalability remains a separate
measured follow-up.

Validation after the final allocator routing: 272 focused Debug internal tests
passed, including allocation-failure sweeps, retained results, partial records,
virtual dispatch, reset and pool relocation. The complete ReleaseSafe program
suite passed 2,362 cases with 11 optional skips, no failures and no leaks. This
includes native/VM and compile-time cases. The new bounded call test performs
128 calls from one outer invocation, allocating write-destination tables without
retaining every transport envelope. It also checks that an earlier public result
still survives another invocation. Scratch
allocation failures leave no unpublished frame/capture backing behind.

Logs: `.zig-cache/runtime-transfers-{before,after}-*-release.csv`,
`.zig-cache/runtime-transfers-throughput-*.csv`, and
`.zig-cache/runtime-transfers-final-{internal,programs}.log`.
