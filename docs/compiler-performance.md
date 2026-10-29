# Measuring compiler frontend performance

## Replacing a live aggregate

The `aggregates` execution scenario repeatedly assigns the result of one reused
function to a single `[16]Int32` session binding. It creates no numbered results
or additional user bindings. Every sample checks that the retained array has
16 elements, all equal to 42. Use it alongside the scalar `calls` control:

```sh
./zig-out/bin/execution-benchmark 1000 minimal aggregates 1024
./zig-out/bin/execution-benchmark 1000 minimal calls 1024
./zig-out/bin/execution-benchmark 10000 minimal aggregates 1024
```

Isolated Linux x86-64 ReleaseSafe runs after `8613c01e3`, with no concurrent
builds or suites:

| Scenario | Commands | Total ms | Retained MiB | Runtime arena bytes | Visible aggregate cells |
|---|---:|---:|---:|---:|---:|
| Aggregates | 1,000 | 533.492 | 17.812 | 1,768,084 | 16 |
| Scalar calls | 1,000 | 479.037 | 16.184 | 1,780 | 0 |
| Aggregates | 10,000 | 34,824.530 | 182.333 | 14,057,702 | 16 |

The aggregate run requests 16,033 complete aggregate cells and 17,017 partial
storage cells at 1,000 commands; at 10,000 these become 160,033 and 170,017.
These counters are cumulative allocation traffic, not live bytes. Visible backing
counts inspect live frames and nested values, not all possible external roots;
they are not a proof that the rest of the arena can be freed. Dead frame slots
remain bounded at 1,848 bytes while identity metadata grows to 2,080,312 bytes
at 10,000 commands. Both completed aggregate runs pass final teardown with zero
requested bytes retained.

This demonstrates immutable payload retention under replacement independently
of growing user results. It does not establish a safe reclamation algorithm.
Any implementation must preserve external results, references, cross-frame
writes, partial/acquired storage and virtual descriptors. Much of the long-run
time is frontend/publication (34,131.414 ms); payload reclamation alone would
not address that cost. The first interrupted long run had no completion status
and is excluded; the repeated long run completed with exit status zero.

## Repeated healthy reset cycles

The `resets` scenario measures complete work/reset cycles rather than a growing
command history. Run with no concurrent suites or benchmarks:

```sh
./zig-out/bin/execution-benchmark 1000 minimal resets 512
./zig-out/bin/execution-benchmark 1000 prelude resets 1024
```

Each cycle defines a function, retains a value and a reference, evaluates two
numbered results across a rejected command, then resets. Prelude cycles also
retain a String owner. Rejection must preserve the graph checkpoint and revision;
reset must restore pool lengths, source-module count and result numbering.
Arena addresses are not compared across reset because their owners are replaced.
The existing teardown check requires zero retained requested bytes after closing
and releasing the whole benchmark.

`# resets` rows report cumulative workload time, its frontend/lowering/verification/
execution breakdown, separate reset time, initial/post-reset requested bytes,
post-reset minimum/maximum and whole-run peak. Setup and the first baseline reset
are outside timings; reset time includes cleanup and prelude reconstruction.
Requested backing bytes include retained prepared core data and arena capacity;
they are not RSS. `--graph-pools` describes the final reset state;
`--resolution-profile` is unsupported for this scenario.

Single ReleaseSafe runs on Linux x86-64, with no concurrent suite or benchmark:

| Mode | Cycles | Work ms | Reset ms | Post-reset bytes | Peak bytes |
|---|---:|---:|---:|---:|---:|
| Minimal | 10 | 16.5 | 4.3 | 8,576 | 124,693 |
| Minimal | 100 | 163.6 | 39.2 | 8,576 | 124,693 |
| Minimal | 1000 | 748.9 | 146.5 | 8,576 | 124,693 |
| Prelude | 10 | 518.6 | 1,108.9 | 132,275,309 | 138,282,362 |
| Prelude | 100 | 5,278.1 | 11,476.5 | 132,275,309 | 138,282,362 |
| Prelude | 1000 | 53,508.3 | 117,485.9 | 132,275,309 | 138,282,362 |

Every observed post-reset value, including the minimum and maximum over all
1,000 cycles, equals its baseline: 8,576 bytes minimal and 132,275,309 bytes with
prelude. Both runs pass the teardown check. A 10-cycle core-only control also
returns to its 125,606,880-byte baseline, and the ordinary calls control passes.
These are lifecycle and retention baselines, not a before/after speed comparison
or evidence about poisoned resets, allocation failures, or unbounded workloads.

## Resolution baseline after compiler consolidation

Single instrumented ReleaseSafe runs on Linux x86-64 at `9ae716638`, using
`execution-benchmark N prelude calls 1024 --resolution-profile`. No test suite
ran concurrently. Times are cumulative command-loop measurements; initial
prelude preparation is outside them. These are a current baseline, not a
controlled comparison against earlier Debug measurements.

| Commands | Total ms | Frontend/publication ms | Lowering ms | Verification ms | Execution ms | Retained MiB |
|---|---:|---:|---:|---:|---:|---:|
| 10 | 61.6 | 55.9 | 2.9 | 2.8 | 0.05 | 126.342 |
| 100 | 626.1 | 564.3 | 30.0 | 31.4 | 0.53 | 127.687 |
| 1,000 | 7,331.6 | 6,610.8 | 373.1 | 341.0 | 6.78 | 142.378 |

The 1,000-command profile records 3,001 fixed-point rounds. Assignment
contextualization visits 151.6 million outer entries and takes 493.6 ms without
reporting a change: typed literals account for 278.4 ms, initializers 43.7 ms,
and writes 171.3 ms. Binding/expression type propagation takes 332.5/307.2 ms,
also without changes. Pending-work checkpoints take 69.8 ms; global unit
verification takes 353.9 ms. Inclusive pass timings overlap and must not be
added to frontend time.

Frontend/publication remains the main cost. These observations support examining
repeated contextualization and propagation before adding caches or changing the
scheduler. They do not attribute all frontend time to those sweeps, prove a
particular complexity bound, or measure improvement from ordered-field lookup.
Retained memory includes the prelude (126.145 MiB before commands).

Raw local logs: `.zig-cache/current-resolution-prelude-{10,100,1000}.csv`.

## Contextualization within an execution unit

Literal and write contextualization now select candidates from the unit's existing
reachable-node set. Candidates are rebuilt each round and sorted by node ID, so
older nodes completed by new facts remain eligible without a persistent cache.
Initializer contextualization retains its full binding scan; compilation without
a closed unit retains the full node scans.

Three alternating ReleaseSafe runs of `execution-benchmark 1000 prelude calls
1024`, comparing `e3aa998f5` with this change on Linux x86-64, measured:

| Measurement | Before | After |
|---|---:|---:|
| Median total command-loop time | 6,459.6 ms | 6,166.7 ms |
| Total time range | 6,418.2–6,469.3 ms | 6,146.3–6,233.3 ms |
| Median frontend/publication time | 5,800.4 ms | 5,504.2 ms |
| Retained memory after 1,000 commands | 142.378 MiB | 142.378 MiB |

Both binaries ran from the installed binary directory against the same core
bundle, with no concurrent test suite. Initial prelude preparation is excluded.
The median total improvement is 4.5% for this workload, not a general compilation
speedup claim.

Separate instrumented runs reduced assignment-context visits from 151,559,519
to 9,763,257 and inclusive time from 469.3 to 78.4 ms. This includes candidate
discovery and the unchanged initializer scan. Typed-literal and write visits
each fell from 71,897,966 to 170,057; fixed-point rounds remained 3,001.

Raw local logs: `.zig-cache/context-unit-controlled-{base,new}-{1,2,3}.csv`,
`.zig-cache/context-candidates-before-profile.csv`, and
`.zig-cache/context-unit-after-profile.csv`.

An earlier attempt rebuilt literal/write candidate lists by scanning the entire
graph once, replacing two full node scans. It reduced outer visits from 151.6
million to about 93.6 million, but inclusive contextualization time increased
from 469.3 to 519.3 ms. A pointer-iteration variant measured 522.8 ms. Unprofiled
total timings did not establish a consistent improvement, so both were discarded.
Fewer counted visits alone did not offset candidate discovery and allocation.
The retained change instead limits discovery to the existing unit dependency set.
These exploratory single-run timings are not controlled throughput comparisons.
Local logs: `.zig-cache/context-candidates-after-{profile,throughput}.csv` and
`.zig-cache/context-candidates-pointer-{profile,throughput}.csv`.

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

In-memory snapshots own their storage independently of source collection arenas.
Compilations hold leases on immutable completed modules, so cache replacement or
eviction does not invalidate active consumers. Releasing the last lease frees the
snapshot arena. This lifetime model supports arbitrary source edits; it does not
depend on append-only REPL publication.

The cache build identity follows literal Zig imports from `src/main.zig` and
hashes embedded files as data. It also includes `build.zig`, the fingerprint
implementation and the LLVM bridge header. Unreachable source files do not affect
that identity; imported files remain included regardless of their names, even
when the import appears in a test declaration. Computed dependency paths fail
explicitly instead of being omitted. Paths are normalized relative to the
checkout, and traversal scratch is released after each parsed file.

## Generic specialization workload

The execution benchmark supports `specializations` and `specialization_reuse`.
Both call the same parameterized function containing 32 locals and conditional
writes. Its integer compile-time tag does not affect its body. The first scenario
uses a different tag per command; the second always uses zero. Compare them with
`branches` for the ordinary-function control. This is a deliberately unfavorable
case for duplicated specialization work, not a representative application.

```sh
./zig-out/bin/execution-benchmark 100 minimal specialization_reuse 1024
./zig-out/bin/execution-benchmark 100 minimal specializations 1024
```

Three alternating, isolated ReleaseSafe runs on Linux x86-64 after `fabe4490b`
measured the following at 100 commands. Setup and teardown are excluded; each
run verifies the retained value, exact instance count and zero tracked backing
after teardown. These compare workloads, not compiler versions.

| Measurement | Reuse one instance | Create 100 instances |
|---|---:|---:|
| Median total time | 34.0 ms | 591.4 ms |
| Total time range | 33.8–34.1 ms | 574.1–618.6 ms |
| Median frontend/publication | 28.3 ms | 348.4 ms |
| Median lowering | 1.6 ms | 45.9 ms |
| Median bytecode verification | 2.9 ms | 194.4 ms |
| Retained backing | 1.915 MiB | 19.509 MiB |
| Semantic graph pool payload | 0.112 MiB | 3.315 MiB |
| Executable arenas | 0.416 MiB | 14.311 MiB |
| Graph nodes / bindings | 966 / 36 | 46,308 / 3,402 |
| Bodies checked / reused | 1 / 99 | 100 / 0 |

`# specializations` rows report commands, matching generic instances, their
top-level body statement count, and total graph nodes/bindings/types. Top-level
statements do not count nested expression nodes. Existing graph-pool and phase
profiles provide separate attribution; neither measures the fraction of a body
that could safely be shared.

In separate instrumented 100-command runs, fresh instances spent 110.2 ms in
resolution and 252.1 ms in checking, versus 11.2/10.1 ms for reuse. Binding and
expression propagation each visited 7.0 million entries without changes, versus
0.22 million for reuse. Inclusive phase times overlap. The 1,000-command runs
also completed with exactly 1,000/one instances and successful teardown; their
timings are excluded from this controlled comparison.

The evidence confirms retained per-instance semantic and executable work, and
effective reuse of an existing instance. It does not establish that shared
semantic subtrees would be a net improvement: fixed signatures, Safety proofs
and bytecode remain specialization-specific. First investigate repeated global
propagation and checking cost; require another measurement before adding a
sharing or invalidation mechanism.

Local logs: `.zig-cache/specialization-reuse-isolated-{1,2,3}.csv`,
`.zig-cache/specializations-isolated-{1,2,3}.csv`,
`.zig-cache/{specialization-reuse,specializations}-profile.csv` and
`.zig-cache/{specialization-reuse,specializations}-long.csv`.

An attempted extension of unit-scoped contextualization to expression type
propagation was discarded before timing. It rebuilt sorted candidates from the
current reachable-node set, while retaining global binding inference. Existing
REPL tests for writes into partially initialized choice payloads then failed:
ownership finalization reached a pointer assignment whose pointer still lacked
a type. The sibling-cleanup exit test failed as well. Thus execution reachability
alone is not a sufficient completion frontier for this earlier propagation pass.
Any future work must account for pending semantic operations and ownership's
requirements, not simply filter completed graph nodes. No candidate cache or
reachability workaround was retained. Local reproduction output is in
`.zig-cache/unit-propagation-tests.log`.

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
inputs and reachability expansion. The reached-input phase was subsequently
removed together with `reach`. The additional entries report timings and
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
| Partial initialization cells and tables | Mutable storage bookkeeping; cells are freed when a complete slot replaces them, call tables on return, session tables on reset |
| Frame/region identity pools and lookup indexes | Context owner's allocator; old resized backing and teardown allocations can be reclaimed |
| Public results, immutable aggregates, projections and virtual descriptors | Value arena; continue to survive until context reset |

IDs and their meanings do not change when pool backing moves. Dead frame IDs
remain dead; reusing buffers does not reuse identities or transfer cleanup flags.
Partial initialization uses the same allocation/release path for call and session
storage. Complete materialized values remain independent arena-owned snapshots.
Publishing a complete session value goes through the ordinary slot write, removing
its previous partial representation only after copying and validation succeed.
This prevents indirect reads from observing stale partial cells after publication;
allocation failures preserve the old cells and their quota. It does not reclaim
immutable snapshots or change public result lifetimes.
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

### Current prelude control

A fresh ReleaseSafe profile at `55680d64f` (Linux x86-64, current installed
core, 1,024 MiB tracked allocation limit) gives these cumulative command times:

| Session | Total ms at 10 / 100 / 1,000 commands | Retained MiB at 1,000 |
|---|---:|---:|
| Prelude calls | 61.2 / 600.9 / 7,148.5 | 144.075 |
| Prelude bindings | 59.8 / 595.6 / 6,985.8 | 142.134 |

These are individual instrumented observations, not a throughput A/B comparison.
Startup and teardown are excluded. The initial retained state is about 127.8 MiB
in both scenarios; command growth must be distinguished from that baseline.

For 1,000 calls, assignment contextualization visits 155.6 million outer entries
without reporting changes and takes 464.6 ms. Binding type materialization takes
321.9 ms and expression propagation takes 297.5 ms. Resolution as a whole takes
2,073.3 ms; frontend/publication takes 6,451.9 ms. Inclusive phase times overlap
and must not be summed. Repeated scans remain a useful target, but their visit
counts alone do not justify replacing the resolver or adding completion caches.

With 1,000 live bindings, continuation fork/seal take 116.8/189.9 ms cumulatively.
They remain more expensive than the call control, but do not dominate this
prelude workload. Use these controls alongside minimal sessions before changing
continuation state or work scheduling.

Logs: `.zig-cache/frontend-current-prelude-profile.log` (100-call control),
`.zig-cache/frontend-current-prelude-1000.csv`, and
`.zig-cache/frontend-current-bindings-1000.csv`. Reproduce with
`zig build benchmark-execution -Doptimize=ReleaseSafe -j16 -- 1000 prelude calls 1024 --resolution-profile`
and substitute `bindings` for the second scenario. Benchmark rows are written to
stderr; redirect that stream when collecting a report.

Generic function constraints are now checked before an instance is published,
through the same instantiation path used by ordinary and selected contract
operations. Unit completion no longer reconstructs substitutions and reselects
those constraints for every historical instance. Deferred body materialization
keeps its already validated arguments. No validation frontier, extra cache or
transaction state is needed; the `generic_function_constraints` profile phase
in the measurements above describes the removed completion pass.

The post-removal 1,000-call control takes 7,092.2 ms overall and 1,010.2 ms
in completion, versus 7,148.5/1,224.6 ms in the preceding control. Retained
memory remains 144.075 MiB, with the same function/instruction counts. The small
total-time difference is insufficient to claim a general throughput improvement;
the concrete result is removal of the repeated validation pass and its temporary
substitution environments. Log: `.zig-cache/generic-constraints-once-profile.csv`.

The partitioned post-state control completes 1,000 prelude calls in 6,452.4 ms
and retains 144.075 MiB, with unchanged function/instruction counts. A separate
100-resource run completes in 970.9 ms, retaining 142.771 MiB and 100 live
acquisitions. These profiled controls exclude startup and are not an A/B speedup
claim. Logs: `.zig-cache/partitioned-post-profile.csv` and
`.zig-cache/partitioned-post-resources.csv`. Post-state joins retain at most three
classes per selected output; distinct output selectors are analyzed independently.

A follow-up ReleaseSafe control at `8d8fc4433` used 100 and 1,000 prelude
calls after the diagnostic-state cleanup. At 1,000 commands it measured
6,914.9 ms total, 6,212.3 ms frontend/publication and 142.410 MiB retained
(startup excluded). Assignment contextualization visited 151.2 million entries
in 469.3 ms without changes; expression propagation took 291.8 ms and binding
initializer inference 21.6 ms. Resolution and completion were 2,102.5 and
984.9 ms inclusive. These single observations do not establish an A/B gain.

The assignment pass has three ordered responsibilities: normalize typed record
literals, contextualize binding initializers, then contextualize direct/indirect
writes. A typed record may still contain unresolved nested lists; a complete
outer type is not a safe permanent completion marker. Preserve same-round
progress and old entities completed by new information when reducing this work.
The profile does not yet separate those three responsibilities, so instrument
that boundary before choosing a worklist or adding retained completion state.
Logs: `.zig-cache/frontend-post-cleanup-profile.log` and
`.zig-cache/frontend-post-cleanup-1000-profile.log`.


The contextualization profile now separates `typed_literal_contexts`,
`initializer_contexts` and `write_contexts` beneath `assignment_values`.
A 1,000-command ReleaseSafe prelude control measured respectively
310.3 / 42.8 / 174.4 ms, with 71.7 / 7.8 / 71.7 million outer entries and
no changes. The enclosing 527.8 ms includes profiling overhead; the new
subphase clocks and counters mean it is not directly comparable to the older
469.3 ms measurement. Total command time was 6,926.3 ms and retained memory
142.410 MiB. Literal and write scans are stronger investigation targets than
initializer contexts in this workload. No worklist or completion cache was
introduced. Log: `.zig-cache/context-phases-prelude-profile.log`.

Scalar-only record completion now rejects the need for recursive shape work
before matching every expected field by name/position. The filter inspects
written and assumed children afresh each sweep, so later aggregate completion
is still visible. Incomplete records also skip the reordering-only pass;
lexical default completion remains unchanged.
A follow-up 1,000-command control measured 264.5 ms typed-literal work and
465.0 ms assignment contextualization, versus 310.3/527.8 ms in the preceding
single sample. Retained memory remained 142.410 MiB. This is directional
single-run evidence, not a controlled throughput comparison. Outer scan counts
are unchanged; no cache, frontier or rollback state was added.
Log: `.zig-cache/scalar-record-completion-profile.log`.

### Baseline after removing reach

At `b23508439`, a ReleaseSafe 1,000-command `prelude calls` control completed
in 6,420.7 ms: frontend/publication 5,737.6 ms, lowering 339.4 ms,
verification 339.1 ms and execution 4.7 ms. Retained requested backing grew
from 143.597 MiB after setup to 159.357 MiB. Setup is excluded from command
timings; these values are not RSS. The 10/100-command totals were
57.4/579.9 ms, retaining 143.694/145.030 MiB respectively.

Assignment contextualization took 86.5 ms, including 8.5 ms typed literals,
42.0 ms initializers and 3.5 ms writes. Its candidate counts differ from the
older controls, so the previous scan timings are not an A/B comparison.
Binding type propagation still visited 86.0 million entries in 329.3 ms;
expression propagation visited 77.8 million in 307.1 ms. Dereference/address
materialization visited the same 77.8 million entries each, taking
163.4/147.5 ms. All these sweeps reported zero changes in this control.

Resolution took 1,616.2 ms and completion 989.2 ms inclusive. Safety took
843.4 ms, while unit verification took 326.6 ms. These are overlapping phase
measurements, not additive shares of total time. The control compiled 1,001
functions and 7,004 instructions, reusing 999 bodies. One function body was
checked and 29,999 body-proof reuses were recorded.

The next investigation should target redundant binding/expression propagation
and address/dereference sweeps, preserving old entities completed by new facts.
The smaller contextualization cost does not justify a new retained cache on
its own. This single observation establishes a current baseline, not a
throughput gain attributable solely to removing reach.

Reproduce with `zig build benchmark-execution -Doptimize=ReleaseSafe -j16 --
1000 prelude calls 1024 --resolution-profile`. Raw output:
`.zig-cache/post-reach-profile.log`.

A follow-up experiment moved the existing binding/type identity check ahead
of the unresolved-binding lookup in expression propagation. The same control
measured 6,391.2 ms overall and 285.0 ms expression propagation, compared
with 6,420.7/307.1 ms above. Pool visits, retained backing and executable counts
were unchanged. The total difference is too small to establish a useful gain
from one sample. The production change was discarded: it does not address the
repeated sweeps. The existing binding test now also checks propagation after
a completed binding changes type and restoration after transactional rollback.
Raw experiment output: `.zig-cache/binding-identity-profile.log`.
