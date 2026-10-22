# Using Argi

## Creating a project

Create and run a program:

```sh
argi init hello
cd hello
argi run
```

`argi init` without a name initializes the current directory; `argi init --lib`
creates a library. Existing files are preserved. The generated entrypoint
sets up allocator, error tracing, and I/O capabilities:

```rg
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi ::= system.ffi
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    assume error_tracer ::= FixedSizeErrorTracer(
        .buffer = view($&zeroed#(.t: [4096]UInt8)()),
    ) | to_virtual#(ErrorTracer)($&_) | $&_
    assume writer ::= $&BufferedWriter#(.base_type: File)(
        .base = $&system.terminal&.stdout,
        .buffer = view($&zeroed#(.t: [4096]UInt8)()),
    )
    assume reader ::= $&system.terminal&.stdin
}
```

## Commands

| Command | Purpose |
| --- | --- |
| `argi build [dir]` | Compile the current package or a selected module. |
| `argi run` | Compile and run the default executable. |
| `argi run --vm <directory>` | Run the experimental scalar/aggregate bytecode subset. |
| `argi check [dir]` | Check all function bodies, including unreachable ones. |
| `argi test [dir]` | Run language-level tests. |
| `argi lsp` | Start the language server. |

Use `--release` with `build` or `run` for optimized executables. See `argi help`
for target selection, output paths, and LLVM/object emission options.

## Packages and build outputs

Packages declare executables in `argi.toml`; outputs go to
`build/debug/<name>`, including when selecting a declared entry module directly.
Standalone modules use `build/output`; test artifacts and reusable compiler
snapshots use `.argi-cache/`. Use `--no-cache` for a fresh frontend build and
`--stats` to inspect module reuse.
See [package configuration](../description/02_modules.md) and
[language-level testing](../description/72_testing.md).

## Formatting and editor support

The LSP provides diagnostics, semantic highlighting, hover, completion,
document symbols, and navigation to definitions.

Run `argi format [paths...]` to format files or directories,
`argi format --check [paths...]` to check without writing, or
`argi format file.rg --stdout` to preview a file. Editors can request document
formatting through `argi lsp`.

See the [source formatting rules](../description/01_source_formatting.md).

## Cross-compilation

Use `--target aarch64-linux-gnu --just-emit-obj output.o` to emit a Linux
ARM64 object; the default target is native. `argi run` requires a compatible
native target. For an ARM64 executable, select a target-configured driver with
`--cc aarch64-linux-gnu-gcc`. `--cc-arg` supplies individual driver arguments
and `--c-sysroot` selects its C sysroot; `--sysroot` still selects Argi core.

## Toolchains and installation paths

Argi uses `cc` (`gcc` on Windows) to link programs. Set `CC` to choose another
compiler. `--sysroot` or `ARGI_SYSROOT` selects another Argi installation prefix;
this is separate from the C toolchain's `--c-sysroot`.

For installation, see the [binary guide](../.github/scripts/binary_installation.md)
or [building from source](../CONTRIBUTING.md#building-from-source).

## Experimental bytecode execution

`argi run --vm <directory>` uses the ordinary frontend, contract selection, and
safety checker, then lowers reachable checked functions to verified bytecode.
It does not emit LLVM, link a binary, or execute unsupported calls natively.
The directory is a folder module; package executable selection and ordinary
build flags are not supported in this mode. `--frontend-jobs N` is accepted.

The initial subset supports fixed-width integers through 64 bits, host-width
`UIntNative`, booleans, string literals, records and fixed-size arrays by value, direct specialized
function calls, local assignments, `if`, `while`, `for`, `break`, `continue`, and
bare `return`. Calls support multiple named outputs through their checked record
result. Boolean operators short-circuit. A program entry has no inputs and either no
result or `status_code: Int32`; its status follows native process truncation.

String literals use immutable UTF-8 backing owned by the execution context,
shared across repeated literals and valid after calls return. `StringView` values
can remain in interactive bindings; reset retires their backing with the context.
Checked reference offsets retain storage identity and enforce concrete bounds.
Text operations that require tracing or other capabilities still require those
capabilities and their bytecode operations to be supported.

Array reads support nested values and returned temporaries. Writes follow local
storage through record fields and array indices, including nested combinations.
Copies are independent values, and all indexing checks bounds at runtime.
An initialized choice inside a partially initialized record supports ordinary
payload borrowing and writes without reading vacant sibling fields. Copied choices
remain independent snapshots; switching variants preserves the other fields.
Local safe references can be passed to and returned from checked calls. They retain
storage identity through record/array projections and can reduce mutable access
to read access. Ended call frames cannot be accessed. References cannot be supplied
as external VM inputs, and results cannot borrow a completed frame. Lexical lifetime
and aliasing rules remain the responsibility of the ordinary safety checker.

Choices support construction, tag tests, active-payload access and `match`,
including borrowed payloads. The verifier checks variant membership and payload
types; execution checks that a payload is active before reading or writing it.
`for` invokes the ordinary selected iterator operations, including borrowed array
iteration and scalar ranges when their checked bodies fit the VM subset.

Automatic cleanup uses the frontend's selected `Deinit` operations, including
scope exits, `return`, loop transfers, structural fields, and active choice payloads.
Whole and partial moves cancel the corresponding source cleanup. Explicit destruction
and outcome-dependent consumption update the same cleanup flags, even for discarded
call results. Destructors must themselves fit the supported execution subset.
Replacing a whole local binding or a statically identified local record field
evaluates the new value before cleaning up the old one. Constant local aliases
of those destinations use the same cleanup, including chains of aliases. The first
initialization does not run a destructor; neighboring fields retain their cleanup.
Explicit destruction followed by definite whole-value reinitialization also works
through reference parameters and reference fields in by-value argument records.
Scalar locals and outputs can be initialized through checked references before
their first read. Function output records and local records support independent
initialization of nested fields, including writes through references to those
fields. Reading a record requires all its fields; initialized siblings can be
read before the record is complete.
Local record storage is cleared on each lexical entry, including loop iterations.
Completing an owning record field by field activates its selected destructor.
An incomplete record instead cleans its initialized owning fields, including on
early exits; it never calls a destructor requiring the absent whole value.
Earlier copies retain their old lifetime and cannot be used again. Whole-value
and record-field owning replacements also work through runtime-selected and
retargetable references. Both backends capture the destination and its cleanup
identity before evaluating the replacement; neighboring fields remain independent.
Owning array elements use the same captured-reference replacement plan. The
array and index are evaluated once before the new value; sibling cleanup remains
independent, including for zero-sized elements. Partially initialized owning
arrays clean only their live elements and nested fields. Completing scalar
fields also updates the enclosing owner's readiness. Scalar and borrowed-only
writes through references work.

Checked `relocate` and trusted opaque relocation transfer values and their
reference evidence using evaluated operands. Existing cleanup obligations move
with the value; inputs and outputs need no automatic local cleanup of their own.
Returned reference records retain their loans across relocation and control flow.

Unary virtual values retain their concrete receiver and the immutable bytecode
unit containing the selected operations. Calls use that evidence directly, including
across REPL submissions; they do not run contract resolution at runtime. Receiver
permissions and storage liveness remain checked. Virtual values cannot escape the
executor as compile-time constants.

`error_location_id()` registers source coordinates in the execution context.
Retained REPL IDs keep their original submitted text across later commands; reset
clears them. These IDs cannot be exported as compile-time constants.
`source_location()` resolves those IDs to immutable path, line text and coordinates.
Unknown IDs stop execution. Error propagation (`!`) preserves the original tracer,
converts reason sets and runs checked early-return cleanup. Context propagation
(`!!`) with a `StringView` evaluates its context only on error and calls the
ordinary core trace helper. `FixedSizeErrorTracer` can record and reset contexts
using its caller-provided byte buffer; complete reporting still needs writer support.

Trusted reinterpretation of initialized numeric records and arrays as `UInt8`
views preserves the original storage, permissions and target byte order. Byte
writes update the numeric value without creating cleanup obligations. Reference
fields and nonnumeric representations remain unsupported.

Referenced globals with constant initializers receive context-owned storage.
Dependencies follow the native initializer plan. Retained REPL globals initialize
once per session and preserve writes across later code units; reset starts fresh.
Globals requiring cleanup and globals without explicit initializers remain rejected.

Embedding hosts can register explicit integer-only foreign-call adapters with
`Vm.initWithHost` or a retained context's `host_bindings` (up to 32 integer
inputs and outputs). Symbols and complete integer signatures must match; missing
or ambiguous adapters reject a command before publication. The logical `ffi`
capability remains checked by the frontend.
Callbacks receive integer copies, and results are range-checked before publication.
Callback failures poison execution. `argi repl` registers stdout/stderr adapters;
`argi run --vm` currently registers none. Registered core heap acquisition and
release primitives use context-owned byte storage instead of native allocation;
raw addresses remain virtual tokens. Checked core establishment can form references
to integers, floats and numeric records/arrays in acquired storage;
reads require initialized bytes and release invalidates every view. Erased anchor
reads check the backing value but expose no concrete representation. Core
`CAllocator` allocations execute ordinary `Allocation` cleanup and release their
context-owned regions. Resource-bearing elements, references stored in acquired
memory and choices still require additional establishment lowering. Compile-time
evaluation continues to reject foreign calls.

Floating values preserve Float16, Float32 and Float64 precision in literals,
arithmetic, comparisons and compile-time results. Byte views and acquired storage
retain their exact representations, including signed zero and NaN payloads.

Raw pointers, C enums, complete trace reporting,
partial choice initialization before selecting a complete variant, vacant arrays
with owning elements, owning globals,
closures,
general foreign calls,
and System capabilities are not yet supported. Unsupported constructs in reachable
function bodies are rejected
before execution, including constructs on untaken branches. Integer arithmetic
wraps at the declared width, matching native execution and constant evaluation.
Division rounds towards zero; `%` is the signed remainder. The signed minimum
divided by -1 wraps to itself, with remainder zero. Division by zero and `abort`
produce source diagnostics. These failures stop execution without running user
destructors; normal lexical cleanup is distinct from abort recovery.

Explicit `#run function(...)` calls use the same executor during compilation,
including native builds. Arguments must be constants; results freeze into compiler
values. References and values requiring cleanup cannot be exported. Compile-time
integer results can supply type shapes and compile-time parameters through staged
semantic resolution. Computed `#if` in function bodies uses the same evaluator;
only the selected arm is materialized for each specialization. See [compile-time computation](../description/50_comptime.md).

Execution is limited to one million instructions, 128 nested calls, and one
million cumulative value cells by default. `argi run --vm` and `argi repl` accept
`--vm-instructions N`, `--vm-call-depth N`, and `--vm-value-cells N` to configure
runtime budgets; zero forbids that work. The REPL prelude uses these same limits
and needs enough budget to initialize. REPL instructions and call depth apply
per command, while value cells accumulate until reset. These flags do not change
compile-time evaluation budgets. Embedders can configure `vm.Limits`
and supply a host-owned `vm.Cancellation` token. Cancellation is checked between
bytecode instructions; blocking host adapters require their own interruption.
Cancelled execution preserves completed writes and host effects, poisons its
context until reset, and does not run user cleanup. Clear the host-owned token
while idle before executing again; context reset does not clear that token.
These limits are not a general sandbox or a stable resource policy. Compile-time
evaluation exposes no host I/O or native handles.
`--vm` selects runtime execution; `#run` and computed conditions execute during
compilation regardless of that option. JIT remains deferred.

## Experimental persistent REPL

Run `argi repl` to load core and start a retained bytecode session. The same VM
subset and execution limits described above apply. `--sysroot <path>` selects an
installation prefix. Input can come from a terminal or a pipe.
At startup, ordinary checked Argi statements create a buffered `error_tracer`.
The terminal displays that prelude; `:reset` cleans the session and executes it
again. The prelude also acquires `ffi` and `Terminal`, borrowing stdout as `writer`,
so `print("hola")` works directly. An ordinary `CAllocator` supplies the persistent
`allocator` assumption. Owning values retain their allocations between commands;
healthy exit and reset run their checked cleanup before releasing the context.
Allocation uses VM regions rather than native pointers; the supported value and
storage restrictions still apply.
In a terminal, Up/Down recall earlier lines and restore the unfinished draft.
Recalled lines can be edited before submission; Ctrl-C cancels the current line
and Ctrl-D on an empty line exits. History lasts for the current REPL process.

`once` consumption is checked across accepted submissions, including calls through
ordinary helpers. Rejected candidates consume nothing, and reset starts a fresh
consumption history. Compile-time evaluation still rejects `once` calls.

Top-level `assume` declarations remain available to calls and selected cleanup in
later submissions. Inner blocks keep lexical assumptions local. Rejected
submissions publish no assumptions; reset clears the session evidence. References
to expression temporaries retain their backing storage until checked session
cleanup, including temporaries created by `assume capability ::= $&acquire()`.
Diagnostics identify unavailable reached inputs in generic calls as well.

```text
>>> value ::= 40 + 2
>>> value
_0 = 42
>>> answer := () -> (.result: Int32) { result = 7 }
>>> answer()
_1 = 7
>>> _0 + _1
_2 = 49
```

Each line is one submission. Use `:begin` and `:end` around multiline definitions
or statement blocks. Submit definitions separately from executable statements.
Functions, types and contracts remain available to subsequent submissions;
redefining accepted names is rejected. Functions use their defining module scope;
session locals enter through parameters or ordinary capability inputs, without
implicit captures. `#run` uses
compiler-known constant expressions, never a snapshot of runtime session storage.
Imports use the normal folder-module loader;
relative paths start at the directory where the REPL was launched. Dependencies
are retained across submissions and reimports; reset allows fresh source loading.
Module-level computed `#if` selects declarations and imports through the same
compile-time execution as native builds. Inactive imports need not exist; failed
selection leaves the accepted session unchanged.

Expressions create constant numbered bindings (`_0`, `_1`, ...), skipping names
already in use. Results, owners and loans remain in the session until reset or
exit; presentation does not copy owners or dereference references. Aggregate
presentation is bounded, StringView results display quoted text, other references
are shown as `<reference>`, and choices use
variant indexes. Type results remain compiler constants, display their type names
and can be reused in queries such as `size_of(.type = _0)`. Neither their storage
nor their identity is materialized in the VM. This is an initial value display, not the text-formatting API.

Scalar, record and array bindings can be declared without an initial
value and written in later commands. Initialized fields and elements can be read
independently of vacant siblings. A complete aggregate can be read once every
field or statically identified element is initialized, including nested fields.
Empty aggregates require an explicit write. Reads of unavailable storage are
rejected before publication. Array layouts keep one element template; concrete
execution cells are charged against the VM's memory limit before allocation.

`:reset` runs checked cleanup and starts a fresh session; `:quit` or EOF cleans up
and exits. Preparation failures publish no state and subsequent input can retry.
Diagnostics for wrapped statements and expression results point to the submitted
text. Unsupported bytecode operations report their source location.
A runtime trap retains any writes already executed and poisons the session; use
`:reset` before continuing. Trapped code cannot be safely unwound. The checked
prelude installs only the capabilities described above; `System` and unrestricted
native calls remain unavailable. Foreign declarations require explicit host
bindings, and their logical `ffi` input still participates in safety checking.

## Measuring retained execution

Build the developer benchmark with `zig build build-execution-benchmark
-Doptimize=ReleaseSafe`. From the repository root, run
`./zig-out/bin/execution-benchmark [commands=1000] [minimal|core|prelude]
[update|bindings|calls|resources|definitions] [memory-limit-MiB=2048]`. It reports checkpoints at 10,
100 and 1,000 commands, plus the final count. Run benchmarks separately from tests.

`minimal` isolates session growth; `core` also retains a prepared bundled-core
module template. `prelude` also executes the CLI's checked prelude, including
its persistent allocator. `resources` requires that mode and retains one 32-byte
`String` plus a scalar marker per command. `definitions` introduces one new
function per command, then calls the last function outside the measured section.
Other scenarios preserve their existing
behavior. Initial preparation, prelude execution, the first binding and teardown
are outside command timings; the zero-command row includes their retained memory.
Frontend/publication time is total command time minus lowering,
verification and execution; verification includes host-binding validation.
Function/instruction totals reveal recompilation across commands.

Live/peak bytes count requested allocator backing, including arena slabs, not
RSS. Checked-graph payload excludes spare capacity and indexes; code, proof and
runtime arena counters identify retained components but are not a partition of
total live memory. `live_acquisitions` and `live_acquired_bytes` count live VM
regions and their extents; `retained_acquired_bytes` includes byte backing and
initialization bitmaps of both live and released regions. These counts overlap
the runtime arena, rather than adding to it. Completed frames are counted separately.
`dead_frame_slot_bytes`
and `live_frame_slot_bytes` count their value-slot payloads.
`dead_cleanup_flag_bytes` and `live_cleanup_flag_bytes` count their separate
compact cleanup buffers; `frame_identity_bytes`
counts the logical frame records (including dead-reference tombstones), excluding
spare capacity and aggregate snapshots. These payload counts overlap the runtime
arena total. The memory limit bounds tracked requested bytes; a run that reaches
it reports the last completed command and fails. Successful runs verify retained
results and complete teardown.

Current snapshot (`629b8044`, Zig 0.16, ReleaseSafe, Linux x86-64):

| Session / command | 0 | 10 | 100 | 1,000 |
|---|---:|---:|---:|---:|
| Minimal / update | 0.05 MiB | 0.51 MiB | 8.13 MiB | 503.26 MiB |
| Minimal / definitions | 0.05 MiB | 0.29 MiB | 2.30 MiB | 19.32 MiB |
| Prelude / update | 151.53 MiB | 208.88 MiB | 727.92 MiB | Not reached |
| Prelude / resources | 151.53 MiB | 225.71 MiB | 1,320.34 MiB | Not reached |

Minimal sessions used a 2,048 MiB tracked limit; prelude sessions used 1,536 MiB.
All processes also had a 3 GiB virtual-address limit. Prelude/update stopped
with OutOfMemory after 170 commands, retaining 1,137.74 MiB after temporary
allocation cleanup. Prelude/resources stopped after 111, retaining 1,510.21 MiB
with a tracked peak of 1,535.69 MiB. The two limits and temporary allocations
mean retained bytes alone do not establish the next command's required memory.
These are bounded failures, not successful 1,000-command runs.

At 100 resource commands, live acquired regions held 4,000 bytes. Checked-graph
payload was 418.35 MiB, code arenas 481.83 MiB, proof arenas 0.68 MiB and the
runtime arena 43,566,044 bytes. The run had compiled 3,300 functions and 76,600
instructions cumulatively. Total command time was 7,099.8 ms: frontend/publication
5,842.6 ms, lowering 513.5 ms, verification 680.0 ms and execution 63.7 ms.
A separate 100-command run completed teardown with no tracked allocations left.
Repeated semantic snapshots and retained code are the main measured costs;
live resources and execution time do not explain the growth.

Minimal/update completed 1,000 commands in 2,171.4 ms, retaining 267.96 MiB of
checked-graph payload and 75.05 MiB of code arenas. Minimal/definitions completed
in 1,754.5 ms and retained only 0.001 MiB of checked-graph payload. Both runs
verified their final results and complete teardown. Single-run timings are
observations, not performance guarantees or AOT compilation benchmarks.

Separating lowering work tables from retained code and replacing empty function
slots with optional immutable descriptor pointers gives the following matched
ReleaseSafe samples under the same limits:

| Workload | Previous live MiB | Current live MiB | Previous code MiB | Current code MiB |
|---|---:|---:|---:|---:|
| Minimal / 1,000 updates | 503.26 | 436.80 | 75.05 | 8.59 |
| Prelude / 100 resources | 1,320.34 | 938.50 | 481.83 | 99.99 |

Lowering's binding/drop maps, cleanup work list, loop patch lists and pending
function lists now use temporary storage in sessions. It is released before
verification and execution; instructions, projections and cleanup layouts retain
their own backing. Published function tables share immutable descriptors without
reserving a complete descriptor for every uncompiled graph function. Existing
units retain their identities and remain immutable when the cache grows.

Both samples preserve their compiled function/instruction counts, checked-graph
payload and runtime storage, verify the retained results and finish with no tracked
allocations left. The resource sample retains the same 100 acquisitions and
4,000 acquired bytes. Command times were 2,270.4 ms for minimal updates and
6,993.3 ms for resources; these single observations do not establish a speedup.
The checked semantic snapshots remain a substantial unresolved scaling cost.

Compact continuation proofs and released checker scratch previously reduced
the ten-resource checkpoint from 319.47 to 229.35 MiB, including a reduction in
proof arenas from 90.17 to 0.06 MiB. The current sample confirms that proof
retention is no longer the dominant component. Further work should reduce
snapshot and code duplication while preserving live identities and resources.

Both definition and continuation publication now discard checker scratch after
checking. Checked call annotations belong to their graph version; only a
continuation's final temporal state needs a separate compact proof. Publishing a
definition does not retain a second arena containing the complete safety analysis.

Scalar host calls carry verified symbol and integer-range descriptors in bytecode.
Linking checks these descriptors against the execution environment without
reconstructing their signatures from the semantic graph. Virtual method tables
also carry verified receiver permissions, so invocation does not inspect a
method parameter type to determine its access.

Finished call frames now make their slot buffers available to later frames of
the same size. Frame identities remain retired, and reused cells and cleanup
flags are reinitialized. Session and acquired storage are not retired by this
mechanism. Cumulative execution-cell budgets are unchanged. A subsequent ten-command
resource run in Debug retained 414,040 bytes of dead-frame slot buffers, versus
4,920,696 bytes in the preceding ReleaseSafe sample. Runtime arena capacity was
7.44 MiB versus 11.18 MiB, with the same 3,148 dead identities, 330 compiled
functions and ten live acquisitions. These are requested storage counts across
different optimization modes, not a timing comparison. The current ReleaseSafe
measurements above include this reuse and the subsequent storage changes.

Repeated acquired-reference establishment reuses an exact immutable view of the
same region, byte offset, logical index, layout descriptor and endianness.
Permissions remain on individual references, and release is checked before a
view can be reused. A storage regression establishing 1,000 aliases previously
retained 1,001 frames; it now retains one, with no additional execution cells.
This does not intern layout descriptors across graph versions or identify
resource cleanup obligations from byte addresses.

Cleanup owners now retain shared immutable layouts instead of a concrete-path
entry for every field and variant. LLVM and bytecode use the same preorder
geometry; the VM follows verified layout projections without semantic-graph
queries. In matched Debug ten-resource samples with a 1,024 MiB tracked limit,
code arenas fell from 15.13 to 11.70 MiB and total retained memory from 226.66 to
223.23 MiB. Runtime capacity, flag bytes, live resources and compiled instruction
counts were unchanged; both runs closed normally with no tracked allocation
retained. These single samples establish storage changes, not a speedup.

Definition submissions now release their checked validation snapshots on
publication; executable submissions retain the graph borrowed by their bytecode.
Both paths use the same checks and atomic semantic publication. A Debug comparison
with the `definitions` scenario and a 1,024 MiB tracked limit measured:

| Definitions | Before retained MiB | After retained MiB |
|---|---:|---:|
| 10 | 0.42 | 0.29 |
| 100 | 7.61 | 2.30 |
| 1,000 | 480.43 | 19.32 |

At 1,000 definitions, retained checked-graph payload fell from 303.28 MiB to
0.001 MiB. Both runs called the final definition successfully and completed normal
cleanup with no tracked memory left. Source arenas still retained 13.45 MiB, and
analysis still repeats accumulated work; this removes unused snapshots rather
than making definition analysis fully incremental. Single-run timings are not
performance guarantees.


Baseline before incremental snapshot consolidation (parent `6135a55a`, Zig 0.16.0,
ReleaseSafe, Linux x86-64, Intel Core Ultra X7 358H). Single-process samples;
timings are observations, not stable performance thresholds. Memory includes
bootstrap state and is reported in MiB of requested backing:

| Workload | Commands | Total ms | Live MiB | Source arena MiB | Checked graph payload MiB | Code arenas MiB |
|---|---:|---:|---:|---:|---:|---:|
| Minimal update | 10 | 15.9 | 0.85 | 0.25 | 0.04 | 0.10 |
| Minimal update | 100 | 238.8 | 25.81 | 12.76 | 2.77 | 2.87 |
| Minimal update | 1,000 | 3,278.5 | 2,517.86 | 1,576.08 | 267.96 | 261.90 |
| Core update | 100 | 3,199.3 | 739.04 | 23.58 | 333.55 | 38.93 |
| Minimal calls | 1,000 | 7,636.0 | 2,954.78 | 1,728.70 | 393.37 | 262.39 |

At 1,000 minimal updates, frontend/publication took 3,125.4 ms, lowering 60.2 ms,
verification 87.3 ms and execution 5.5 ms. Runtime storage retained 898,428 bytes
and 1,001 dead frames. The call workload compiled 2,000 functions for 1,000
commands, including the same helper on each command. Source snapshot storage,
checked graphs and code-unit retention dominate these examples; VM execution
and dead frame bytes are not the first scaling bottleneck.

The 1,000-command samples used a 4,096 MiB limit, for example
`./zig-out/bin/execution-benchmark 1000 minimal update 4096`. In that baseline,
the default 2,048 MiB limit stops minimal updates after 954 commands and core
updates after 296 commands. These failures are retained-memory measurements, not VM
instruction-budget exhaustion.

After sharing append-only module-prefix buffers and growing source indexes
geometrically, the same 1,000 minimal updates retain 713.14 MiB: source arena
13.45 MiB, diagnostic arena 0.87 MiB, checked graph payload 267.96 MiB and code
arenas 261.90 MiB. The sample takes 2,328.1 ms (2,181.5 ms frontend/publication).
Core at 100 commands retains 708.11 MiB. Retained memory is still not linear.
Earlier snapshots and branched/rejected histories keep their original module
headers; source IDs and original diagnostic buffers remain unchanged.

After verifier linear-state transfer, a 1,000-command minimal call sample
retains 930.89 MiB (932.53 MiB peak) within a 1,536 MiB limit. Completed-frame
slots account for 440,088 bytes, live-frame slots for 88 bytes, and logical frame
records for 160,160 bytes. The entire runtime arena holds 2,220,156 bytes;
checked-graph payload and code arenas account for 393.37 and 262.44 MiB.
The run compiles 2,000 functions and 11,000 instructions: the helper is still
regenerated for each command. This sample prioritizes snapshot/code reuse over
frame-slot reclamation; it does not establish bounds for aggregate-heavy code.
Observed total time is 24,358 ms, including 23,799 ms frontend/publication,
242 ms lowering, 287 ms verification and 30 ms execution. Timing comparisons
across these samples are not controlled benchmarks.

Publishing function tables directly and copying them only when a retained lowerer
adds a new function reduces the same 1,000-call sample to 743.70 MiB live
(745.36 MiB peak). Code arenas fall from 262.44 to 75.26 MiB; checked graphs,
proofs, frame storage and compiled function/instruction counts are unchanged.
Observed total time is 23,019 ms, including 147 ms lowering. This removes one
redundant table snapshot per command without reusing function bodies across
commands; semantic snapshots remain the largest measured component.

To isolate verifier allocation behavior, run
`zig build benchmark-execution -Doptimize=ReleaseSafe -- --verifier`.
It constructs linear functions and chains of diamonds with 10, 100 and 1,000
Boolean slots. Each diamond has two paths merging before the next branch.
Graph/code construction is excluded from the measured allocator. The output
distinguishes cumulative requested bytes, peak live requested bytes and bytes
still owned after verification; these are not RSS measurements.

One native ReleaseSafe sample reports:

| Shape | Slots | Instructions | Requested bytes | Peak bytes | Retained bytes |
|---|---:|---:|---:|---:|---:|
| Linear | 10 | 11 | 681 | 539 | 0 |
| Diamonds | 10 | 31 | 4,101 | 1,219 | 0 |
| Linear | 100 | 101 | 3,021 | 2,789 | 0 |
| Diamonds | 100 | 301 | 64,721 | 28,089 | 0 |
| Linear | 1,000 | 1,001 | 26,421 | 25,289 | 0 |
| Diamonds | 1,000 | 3,001 | 3,342,561 | 2,077,429 | 0 |

Linear state transfer avoids one full slot vector per instruction. Joins still
retain full vectors: the diamond workload grows with both join count and slot
count. This synthetic sample identifies that remaining scaling cost; it does
not establish its contribution to ordinary REPL workloads or justify changing
the representation by itself. Observed verification time at 1,000 slots was
0.86 ms for linear code and 27.52 ms for diamonds, without a timing threshold.
