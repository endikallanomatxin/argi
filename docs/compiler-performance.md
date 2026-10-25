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
because later contextualization can change operand types.

Arithmetic propagation skips coercion and representation queries when both
operands and the result already carry the same resolved type ID. A later operand
type change takes the ordinary path again. No worklist or completion cache is
introduced for expressions. Timing comparisons for these subpasses remain to be
collected without an active test suite; no speedup is claimed here.
