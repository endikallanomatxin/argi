# Shared execution for REPL and comptime

## Direction

Use a bytecode VM and a JIT compiler as two executors of the same checked Argi
program. Interactive sessions and compile-time evaluation share this machinery,
while supplying different capabilities, result-persistence rules, and limits.
The existing ahead-of-time LLVM path remains a parity reference and deployment
backend. Release ordering belongs in the version plans.

## Architecture and dependencies

Lower resolved, ownership-checked semantizing results into a typed bytecode
representation. Bytecode needs explicit call, branch, storage, cleanup, and
source-location information; it must not reinterpret source syntax or duplicate
semantizing decisions. Begin with a verified representation and a complete VM
path for the supported subset before adding native execution.

Use the existing LLVM infrastructure for the JIT where practical. Define one
execution contract for values, aggregates, references, output lifetime checks,
errors, and host operations. VM frames need not use identical physical storage
to LLVM frames, but boundary adapters must preserve the same ownership and
lifetime facts. A host bridge does not grant FFI permission by itself.

Keep function identities independent of their executor. Calls resolve through
session-owned executable entries, allowing functions to start in bytecode and
later acquire native code. Native-to-VM entry requires a trampoline; VM-to-native
entry requires a checked adapter. Decide supported signatures explicitly before
extending aggregate, callback, or virtual boundaries.

Bytecode is an execution artifact, distinct from canonical ModuleSG snapshots.
Specify verification and versioning before persisting it. Native code and its
symbol dependencies need an owner that outlives every live executable reference.
Do not unload or replace code merely because a source revision was discarded.

## Session state

Separate checked definitions from executed values. A rejected submission must
not partially update the definition environment. Successful evaluation may
retain values and their storage roots in session-owned regions, with ordered
cleanup on reset or exit. Persistent roots must participate in ordinary lifetime
checking; moving a value between submissions must preserve its dependencies.

Redefinition requires an explicit policy for existing values, function pointers,
and imports. Initially reject changes that invalidate live dependencies rather
than attempting value migration. A runtime error can release submission-local
owners and continue the session; externally visible effects already performed
cannot generally be rolled back.

REPL display and diagnostics should work for incomplete input without executing
it. Keep editor-time evaluation bounded and cancellable at defined safe points;
a blocking foreign call cannot be interrupted by an instruction budget alone.

## Compile-time boundary

The language contract for `#run` and `#if` is in
[compile-time computation](../description/50_comptime.md). Settle its open effect
and diagnostic questions before exposing a general evaluator. Compile-time
execution receives only the capabilities allowed by that policy; runtime System
or FFI permissions are not inherited implicitly.

Freeze supported results into compiler-owned constants. Copy aggregate contents
and preserve nominal type identity; reject escaped VM addresses, native handles,
and references to evaluator-local storage. Compiler type values may require
explicit meta-values rather than runtime layout tricks.

The evaluator runs on the host while computing for the selected compilation
target. Target C aliases, layout queries, integer widths, and target predicates
must come from the compilation target. Use target-aware bytecode operations and
reject unsupported native cross-target operations. Host JIT execution cannot be
assumed to implement target memory layout transparently.

Cache permitted external inputs and effect policy along with source, target,
compiler, and bytecode identity. Define step/recursion, memory, and time budgets;
report limits as evaluation diagnostics with source and call information.

## Remaining decisions and work

- [ ] Specify the initial executable subset and classify unsupported constructs.
- [ ] Design typed instructions, verification, frames, and storage representation.
- [ ] Define shared VM/native call adapters and native-code lifetime roots.
- [ ] Choose LLVM JIT integration and symbol/host-call resolution mechanisms.
- [ ] Settle session persistence, redefinition, reset, and failure recovery.
- [ ] Settle comptime effects, frozen results, target emulation, and cache inputs.
- [ ] Measure cold evaluation and repeated calls before choosing promotion
  thresholds; retain forced executor modes for deterministic parity tests.
- [ ] Exercise values, aggregates, generic/virtual calls, errors, cleanup,
  output lifetime checks, and supported C boundaries against ahead-of-time fixtures.

Transparent live-value migration, arbitrary hot replacement, background native
compilation, and tiered optimization beyond the first VM/JIT boundary are later
extensions. Concurrency does not require them.
