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
main := (.system: System) -> (.status_code: Int32 = 0)  {
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
| `argi build [dir]` | Compile the current module or a selected module. |
| `argi run` | Compile and run the default executable. |
| `argi run --vm <directory>` | Run the experimental scalar/aggregate bytecode subset. |
| `argi check [dir]` | Check all function bodies, including unreachable ones. |
| `argi test [dir]` | Run language-level tests. |
| `argi lsp` | Start the language server. |

Use `--release` with `build` or `run` for optimized executables. See `argi help`
for target selection, output paths, and LLVM/object emission options.

## Module configuration and build outputs

Modules declare executables in `argi.toml`; outputs go to
`build/debug/<name>`, including when selecting a declared entry module directly.
Standalone modules use `build/output`; test artifacts and reusable compiler
snapshots use `.argi-cache/`. Use `--no-cache` for a fresh frontend build and
`--stats` to inspect module reuse.
See [module configuration](../description/02_modules.md) and
[language-level testing](../description/72_testing.md).

`argi.toml` is optional and does not make a module distributable. Only an
explicit `[distribution]` declares distribution identity; it does not publish
anything. Submodules share their distribution's version and dependencies.
Exact dependency resolutions belong in an automatically managed `[lock]` section
of `argi.toml`, marked with a comment; there is no separate lockfile.
Dependency resolution, managed `[lock]` updates, and programmable `build.rg` automation
are specified but not implemented yet.

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
Selected integer `Convert` operations retain core range checks and execute
sign extension, zero extension or truncation with the declared widths. These
conversions also work inside `#run`; range failures preserve the original tracer.

String literals use immutable UTF-8 backing owned by the execution context,
shared across repeated literals and valid after calls return. `StringView` values
can remain in interactive bindings; reset retires their backing with the context.
Checked reference offsets retain storage identity and enforce concrete bounds.
Computing an offset does not read or initialize its destination; values are
required only when the resulting reference is read.
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
including borrowed payloads. Fallible aggregate and argument construction retains
evaluated operands in lexical owners until transfer, so early propagation cleans
previous operands without invoking a destructor on an incomplete whole value.
The verifier checks variant membership and payload
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
Call summaries retain those entry-relative destinations even when the replacement
retargets a reference field. Reinitialization renews only the selected reference;
historical copies remain stale.
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
raw addresses remain virtual tokens. Checked core establishment forms references
to prepared values in acquired storage. Allocation slots carry receipt descriptors;
selection stays within that receipt's authenticated extent even when other regions
are live. Numeric reference offsets
retain the intersection of declared and authenticated byte extents; selecting an
element does not read or initialize it. Reads require initialized bytes, and
release invalidates every view. Erased anchor
reads check the backing value but expose no concrete representation. Core
`CAllocator` allocations execute ordinary `Allocation` cleanup and release their
context-owned regions. Typed allocations prepare independent slot state for
supported records, arrays and regular choices, with or without cleanup, including zero-sized elements.
Opaque initialization, extraction and destruction preserve those obligations
across calls and REPL submissions. Partially initialized or consumed aggregates
clean only their remaining live children; an incomplete choice retains its active
variant without requiring a complete payload. Acquired aggregates may also contain
safe references and virtual values. Prepared slots retain reference evidence and
the original selected virtual code unit and operation table. Physical writes revoke
only reference leaves whose bytes they touch; touching a choice tag revokes all
reference evidence for that choice. Only the selected payload must be initialized.
Reference representation bytes are
opaque in the VM: byte copies neither serialize nor reconstruct that evidence.
Compile-time entries without `System` continue to reject foreign calls.

Floating values preserve Float16, Float32 and Float64 precision in literals,
arithmetic, comparisons and compile-time results. Byte views and acquired storage
retain their exact representations, including signed zero and NaN payloads.

Raw pointers, C enums, complete trace reporting,
partial choice initialization before selecting a complete variant, owning globals,
closures,
general foreign calls,
and runtime `System` entrypoints are not yet supported by `run --vm`. Unsupported constructs in reachable
function bodies are rejected
before execution, including constructs on untaken branches. Integer arithmetic
wraps at the declared width, matching native execution and constant evaluation.
Division rounds towards zero; `%` is the signed remainder. The signed minimum
divided by -1 wraps to itself, with remainder zero. Division by zero and `abort`
produce source diagnostics. These failures stop execution without running user
destructors; normal lexical cleanup is distinct from abort recovery.

Anonymous `#run { ... }` entries use the same executor during compilation,
including native builds. They can declare ordinary output signatures; captured
values must be known at compile time, and results freeze into compiler values. References and values requiring cleanup cannot be exported. Compile-time
integer results can supply type shapes and compile-time parameters through staged
semantic resolution. Computed `#if` in function bodies uses the same evaluator;
only the selected arm is materialized for each specialization. See [compile-time computation](../description/50_comptime.md).

`#run (.system: System)` entries construct and clean their resources in
an ordinary checked scope. They enable stdout/stderr adapters and context-owned
allocation; the entry must explicitly assume its writer, allocator and tracer.
Each invocation has an independent acquisition scope. Host arguments are empty.
Filesystem, environment, stdin, network, processes, clock and entropy calls are
not enabled; unavailable adapters reject evaluation before any host operation runs.
External reads require build-dependency tracking before they can be enabled.
Generic entries retain their specialization parameters and selected captures;
rejected runtime captures publish no interactive revision.

Execution is limited to one million instructions, 128 nested calls, and one
million retained value cells by default. `argi run --vm` and `argi repl` accept
`--vm-instructions N`, `--vm-call-depth N`, and `--vm-value-cells N` to configure
runtime budgets; zero forbids that work. The REPL prelude uses these same limits
and needs enough budget to initialize. REPL instructions and call depth apply
per command. Frame identities and immutable snapshots accumulate until reset;
reused call buffers are charged once. These flags do not change
compile-time evaluation budgets. Embedders can configure `vm.Limits`
and supply a host-owned `vm.Cancellation` token. Cancellation is checked between
bytecode instructions; blocking host adapters require their own interruption.
Cancelled execution preserves completed writes and host effects, poisons its
context until reset, and does not run user cleanup. Clear the host-owned token
while idle before executing again; context reset does not clear that token.
During bytecode execution, Ctrl-C requests cooperative cancellation in both CLI
commands. `argi run --vm` reports cancellation and exits with status 130. In the
REPL, use `:reset` to clear the CLI token and rebuild the cancelled session.
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
Terminal input uses lexical syntax colors; `NO_COLOR` or `TERM=dumb` disables
colors. Continuing inside braces inserts four spaces per nesting level, and a
closing `}` typed on the untouched indentation dedents one level. Braces in
comments and strings do not affect indentation; continued strings receive no
inserted spaces. These editor features do not alter piped input.
In a terminal, Up/Down recall earlier lines and restore the unfinished draft.
Left/Right move by UTF-8 character; Backspace and Delete remove the character
before or under the cursor. Home/End move to the line boundaries.
Recalled lines can be edited before submission; Ctrl-C discards the current line
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

Open parentheses, brackets, braces and quoted literals continue a submission
on the following line. Terminal prompts change to `...` until the input closes;
comments and quoted delimiters do not change the nesting. Use `:begin` and `:end`
for an explicit batch, including multiple complete statements. `:cancel` discards
a pending automatic or explicit batch; Ctrl-C does the same while editing in a
terminal. Accepted values remain live, and unsubmitted statements never execute.
Submit definitions
separately from executable statements.
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
presentation is bounded, records show field names, and choices show variant
names with their payloads. StringView results display quoted text; other references
are shown as `<reference>`. Type results remain compiler constants, display their type names
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
`:reset` before continuing. Trapped code cannot be safely unwound. Cleanup used
by reset and exit follows the same boundary: failure to prepare it
preserves live owners and permits retry, without accumulating rejected sources.
A trap during cleanup requires another reset, which releases context-owned
memory without retrying user destructors or undoing external effects. The checked
prelude installs only the capabilities described above; `System` and unrestricted
native calls remain unavailable. Foreign declarations require explicit host
bindings, and their logical `ffi` input still participates in safety checking.

## Measuring retained execution

Build the developer benchmark with `zig build build-execution-benchmark
-Doptimize=ReleaseSafe`. From the repository root, run
`./zig-out/bin/execution-benchmark [commands=1000] [minimal|core|prelude]
[update|bindings|calls|resources|definitions|rejections] [memory-limit-MiB=2048]`. It reports checkpoints at 10,
100 and 1,000 commands, plus the final count. Run benchmarks separately from tests.

`minimal` isolates session growth; `core` also retains a prepared bundled-core
module template. `prelude` also executes the CLI's checked prelude, including
its persistent allocator. `resources` requires that mode and retains one 32-byte
`String` plus a scalar marker per command. `definitions` introduces one new
function per command, then calls the last function outside the measured section.
`rejections` repeatedly submits an unresolved call and checks that the graph
checkpoint and accepted revision remain unchanged. It measures rejected source
and diagnostic retention separately from accepted semantic growth. Initial preparation, prelude execution, the first binding and teardown
are outside command timings; the zero-command row includes their retained memory.
Frontend/publication time is total command time minus lowering,
verification and execution; verification includes host-binding validation.
Function/instruction totals reveal recompilation across commands.
Append `--graph-pools` to report the shared semantic graph columns as comment
rows: `# graph_pool,commands,name,payload_bytes,reserved_bytes`. These rows
exclude nested slices, lookup tables and safety arenas; they attribute flat
pool backing only and do not add to the allocation totals above. The diagnostic
runs after command timing and introduces no instrumentation in normal sessions.

Live/peak bytes count requested allocator backing, including arena slabs, not
RSS. Semantic-graph payload excludes spare capacity and indexes; code, proof and
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

For a synthetic verifier-only allocation probe, run
`zig build benchmark-execution -Doptimize=ReleaseSafe -- --verifier`.
The run step builds and executes its own artifact; it does not update an older
benchmark installed under `zig-out/bin`.

Each retained session owns one append-only semantic graph. Commands add to it
inside coordinated transactions covering graph pools, completions, resolver
caches and scheduling state. Rejection restores the accepted state. Unit
reachability and execution annotations are separate from the graph; completing
one unit does not discard unrelated function bodies.

Safety summaries retain selector, callee and virtual-contract hypotheses.
Body proofs own their execution annotations and the converged hypotheses they
consulted. A changed hypothesis requires checking again; continuations and
caller temporal facts are always checked. `summary_evaluations`,
`summary_reuses`, `summary_entries` and `summary_arenas_MiB` report summary work.
`bodies_checked`, `bodies_reused`, `body_proof_entries` and
`body_proof_arenas_MiB` report body proofs separately.

Executable units import immutable verified helper bodies through their original
units, preserving host bindings, globals, session layouts and virtual tables.
Reuse checks proof revisions across the call closure, including virtual methods
and global-initializer helpers. A callee's changed proof can require re-lowering
even when the caller's summary remains equal. These are publication revisions,
not semantic body versions. `reused_functions` counts imported entries; compiled
function/instruction counters include only new bodies. No executable unit owns
a historical semantic-graph snapshot.

Compile-time evaluation uses nested graph transactions to discard temporary
Safety projections before publishing constant outputs. VM initialization prepares
external-input descriptors; invocations check scalar widths, aggregates and
choice payloads through those descriptors. External references and virtual
handles remain rejected at that boundary.

Rejected submissions retain their latest diagnostic batch until the next entry.
Accepted source batches remain alive for published code. Rejected module graphs,
selection caches and source-index tails are discarded together. Message storage
is separate from persistent source indexes. `source_arenas_MiB` includes all live
source batches; `diagnostic_arenas_MiB` measures message arenas, excluding indexes.

Measurements for `039a77a8` (Zig 0.16, Debug, Linux x86-64, 1,024 MiB tracked limit):

| Session / scenario | Commands | Live MiB | Peak MiB | Graph payload MiB | Code arenas MiB |
|---|---:|---:|---:|---:|---:|
| Minimal / calls | 1,000 | 18.066 | 18.082 | 0.605 | 2.736 |
| Prelude / resources | 100 | 188.536 | 190.655 | 3.367 | 3.330 |
| Minimal / rejections | 1,000 | 0.038 | 0.050 | 0.001 | 0.001 |

| Scenario | Total ms | Frontend/publication ms | Lowering ms | Verification ms | Execution ms |
|---|---:|---:|---:|---:|---:|
| Calls | 22,086.7 | 20,828.9 | 479.4 | 682.8 | 95.5 |
| Resources | 33,234.1 | 28,403.8 | 1,985.7 | 2,044.8 | 799.9 |
| Rejections | 2,412.6 | 2,412.6 | 0 | 0 | 0 |

The 1,000-call session compiles 1,001 bodies: one helper and one new command body
per submission. It reuses that helper and its body proof 999 times, retaining
one body proof. The resource session compiles 130 bodies and 1,874 instructions,
checks 27 new bodies and reuses 5,573 body proofs. It retains 106 body proofs in
0.567 MiB and 118 summaries in 0.234 MiB. Its 100 live acquisitions hold 4,000
bytes; startup/core preparation and the live runtime are included in total
retained memory.

Rejected-command backing remains at 0.038 MiB at 10, 100 and 1,000 commands,
while accepted graph and revision checkpoints stay unchanged. Every run verifies
its retained result and releases all tracked backing at teardown. These are
individual observations, not throughput guarantees or AOT compilation timings.
Frontend scaling and recovery of dead runtime frames remain further work;
completed frame payloads currently remain until context reset.

VM runtime failures include up to 64 active source frames, starting at the
failing instruction and followed by `called from` locations. CLI execution and
REPL submissions share this presentation. Compile-time failures retain these
locations after evaluator teardown and report them through the scheduler.
Trace capture is best-effort under
allocation failure, stores no language values and performs no unwinding. A
trapped REPL still requires reset; its saved failure trace is not resumable state.

### Project test suites

Declare the modules run by `argi test` in the current directory's `argi.toml`:

```toml
[test]
modules = [
    "tests/unit",
    "tests/integration",
]
```

Paths are relative to the manifest. Each entry selects one folder-level module;
subdirectories are not searched recursively. Modules run in the configured order.
`argi test path/to/module` overrides the configured suite, and `argi test .`
explicitly tests the current module. Without a configured suite or an explicit
path, the command reports how to select modules instead of scanning the project.
An empty suite reports no tests found and exits with status 1.

`--filter text` applies to test names in either form. Results include the module
path and test name, for example `PASS /project/tests/unit/example`, so identical
names in different modules remain distinguishable. A failed test causes the
command to exit with status 1 after running the remaining selected tests.
