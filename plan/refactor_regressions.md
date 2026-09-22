# Compact graph refactor: regression handoff

## Current checkpoint (2026-09-14)

This document's original checkpoint below records the 2026-09-09 state; its
test counts and file paths are historical. Development continues on
`compact-semantic-graph-chatgpt`, using `performance` as the behavior reference.

### Open language-design question: calls through erased abstract values

The remaining String concatenation failures expose a boundary that should not
be papered over as generic-inference fallout. `concat_views` obtains an
`allocator: $&Allocator` through `#reach` and calls the free function
`string_with_capacity`, whose abstract input makes it an abstract-contract
template. The caller now has only the erased abstract type, while contract
specialization deliberately requires a concrete implementer. The source
contract declaration has no executable ABI, so selecting it as an ordinary
function is not a valid fallback either.

Before implementing this path, the language needs to choose one of these
semantics (or define another explicitly): preserve the concrete backing type
through typed `#reach` bindings so the free function remains statically
specialized; permit a runtime/virtual specialization of free functions over an
erased abstract value; or reject such calls and require the abstraction to
expose the operation as a virtual requirement. This affects representation,
dispatch, and codegen ABI. Do not relax constrained generic inference to bind
an abstract declaration as its own implementer merely to make these tests pass.

### Open language-design question: canonical identity for the non-movable System capability

`feature_tests/ownership/35X_system_move_by_value` specifies that `System`
cannot be moved by value even with an explicit `~`; callers must pass a
reference. The compact graph currently represents `System` as an ordinary
nominal core declaration. Unlike primitive builtins, it has no canonical role
or capability bit that the ownership checker can test. Implementing the rule
by comparing the declaration's displayed name would also forbid unrelated
user declarations named `System` and would make semantics depend on spelling.

Before restoring this diagnostic, decide where core capability identities live
after module globalization. Plausible directions include a canonical core
declaration table or an explicit non-movable type property. The ownership pass
should consume that identity/property; it should not rediscover the rule by a
global string search.

Current examples are `feature_tests/text/12_string_concat` through
`text/17_string_view_concat_string`; `text/16` and `text/17` expose the direct
`string_with_capacity(.allocator: $&Allocator, .capacity: UIntNative)` case.
The binary operator pipeline now selects the intended overload for `text/12`
through `text/15`, applies contextual string-literal coercion, and preserves
the `Errable` output type. Those tests consequently converge on the same
erased-allocator specialization boundary rather than failing earlier as
pointer arithmetic or with a stale `&String` binding type.

ModuleSema now recognizes a same-module abstract input as a constrained
parameterized function. It retains the source declaration as a bodyless
contract interface and lowers the executable body once as a template;
GlobalSema infers a concrete implementer at each call and materializes a
separate concrete function instance. This restores the local part of the
pre-refactor abstract monomorphization algorithm. Imported abstract inputs
remain unresolved: their declaration identity and concrete `#reach` backing
type must be carried across module boundaries before applying the same rule.
GlobalSema now refuses to bind a constrained type parameter to the abstract
contract declaration itself. During an attempted core-wide catalog pass,
`string_with_capacity` otherwise acquired an `Allocator`-as-implementer
instance and failed contract validation. The catalog pass was withdrawn:
`#reach` defaults must first be resolved in the caller's indexed binding
context, then the selected concrete type can drive specialization. No core
contract names are hardcoded into the lowering path.
Parameterized ModuleSema now retains `#reach` alternatives and path segments
in its own indexed IR when they appear as function input defaults. This data
was previously dropped by the template body lowerer. Parameterized input and
output bindings now retain their default initializers as well. Generic dispatch
uses the presence of those defaults while scoring an omitted argument, then
the selected instance receives its own concrete default nodes without mutating
an interned structural type. Instantiated `#reach` alternatives are resolved
against the ordinary caller scope by the same GlobalSema path as non-generic
calls.
Ordinary ModuleSema call operations capture the binding IDs visible at the
call site in lexical order. GlobalSema consumes that scope when completing
reached defaults. Missing values still require propagation through the
enclosing function's input.
GlobalSema now rejects a named argument that does not occur in a candidate's
input fields before scoring its defaults. This prevents `.self` from selecting
an unrelated `flush(.stdout = #reach ...)` overload and blocking the next
dispatch strategy. The same shape check applies to abstract-compatible calls.
GlobalSema now resolves ordinary `#reach` defaults from the bindings captured
at the call site, walking alternatives and nested field paths in source order.
It completes the chosen call with a new argument node and does not mutate the
callee's shared default. A local executable semantic fixture passes. The
internal suite currently has 164 passing tests and one LSP crash: the only
remaining pending path in that fixture is `System.deinit` calling
`Terminal.deinit` without an allocator visible in the local scope. The old
compiler propagated that reached field into the enclosing function input;
GlobalSema now restores that propagation by extending the enclosing function's
input fields and input bindings, then resolving the outer call on the next
fixed-point iteration. A two-level regression test passes, all 165 internal
tests pass, and the minimal program advances beyond `System.deinit` to the
imported abstract signature in `write_trace_text`.
The frontend derives an abstract declaration catalog from the loaded syntax
files and passes it into each ModuleSema invocation. Imported abstract inputs
are now lowered as constrained parameterized templates through an external
declaration reference; no core contract names or hidden `system` lookup are
hardcoded. The minimal program consequently advances beyond the former
`write_trace_text` codegen signature failure, but exhaustive core bodies still
leave unrelated string operations pending. Selective reachability/root-context
construction remains necessary, and functions with explicit generic
parameters now append implicit constrained parameters instead of choosing only
one parameter category. Explicit dispatch binds supplied arguments, infers the
remaining contract parameters from the call input, and publishes the complete
substitution list used as the concrete instance identity.
Abstract contracts nested inside ordinary generic type arguments are also
collected as constrained type parameters. `Virtual#(.abstract: ...)` is an
exception because its abstract argument selects a runtime vtable rather than
a concrete representation to infer. Both ModuleSema type lowering and
parameterized lowering classify the constructor as a virtual runtime type;
the parameterized IR retains its virtual type instead of encoding a generic
instantiation. The nested-pattern and runtime-contract tests pass, and the
internal suite remains green (161 tests).

The ownership pass now preserves the owning aggregate when projecting fields,
retains opaque provenance through address formation, and lowers field writes
through storage addresses. The opaque mutation negative fixtures 140X, 142X,
143X, 144X, and 146X pass. Positive fixtures 141 and 145 are still blocked
at codegen by a shared abstract runtime type problem, so ownership parity is
not yet established end to end.
GlobalSema now also fixes the backing type of an abstract struct field from its
first concrete pointer assignment, propagates that representation to stores
and field accesses, and rejects a later assignment selecting a different
concrete implementer. This restores the static-layout algorithm independently
of the remaining abstract-parameter specialization work.

GlobalSema now contextualizes typed literal assignment and initialization,
coerces default integer constants to the typed operand for arithmetic, and
reports a unique generic candidate's conflicting repeated type argument
deterministically. The corresponding internal tests pass. Other pending-call
classes still require comparison with `performance`.
Generic input unification now also binds comptime integer parameters carried by
generic type arguments and array lengths. Repeated occurrences must agree, and
dependent binary expressions are checked once their operands have bindings.
Type parameters are recursively inferred through nullable and inferred-errable
wrappers, and structural patterns now require every declared pattern field to
match instead of silently accepting a missing field.
Source syntax still accepts only literal array lengths, so the array path is
covered at the parameterized IR boundary until dependent array syntax is
restored.
ModuleSG records the owning function beside every pending body operation.
Interface, declaration, and module-root work retains a null owner and is always
eligible for global resolution. This explicit ownership table is the boundary
needed for GlobalSema to activate work by entrypoint reachability without
reconstructing lexical ownership from node allocation order.
ModuleSG no longer requires local generic shapes for every resolved generic
type. Those types are durable materialization requests whose canonical
declaration may only be known after modules are linked; GlobalSema remains the
owner of complete shape materialization and GlobalSG verification still checks
the one-shape-per-generic invariant. The local generic struct fixture now
passes ModuleSema and advances to the shared imported abstract-contract blocker.

The error model remains incomplete. Indexed error propagation and context
records now have codegen control flow, and `testing_expect_error` is lowered by
GlobalSema and codegen. Runtime trace entries are appended for propagation,
context, and expect-error failures in the indexed graph.
GlobalSema now follows nested expressions (including binding initializers) to
find the enclosing return type, checks that the caller returns an errable
value, validates concrete reason supersets and trace type compatibility, and
restricts `!!` contexts to read-only character pointers or `StringView`.
Inferred `!T` carries an open reason choice and an `ErrorTrace` field instead
of an `Any` payload. Contextual reason literals and propagated reasons extend
that choice through new contiguous variant ranges. The former inferred-error
fixture now reaches codegen. Trace entries include diagnostic line and column
data.

Codegen now contains the indexed propagation control flow: it branches on the
errable tag, executes recorded cleanup on the error path, rebuilds the caller's
errable, and unwraps the success payload. Propagation compares source tags by
their choice-local index, remaps reason tags by name into the caller's superset,
preserves the trace field, and packs the result according to the function ABI.
Codegen derives propagation metadata from `SourceDb`, grows and relocates the
trace's `DynamicArray`, and appends the source location and optional `!!`
context before remapping the payload. GlobalSema lowers
`testing.expect_error` into its indexed semantic payload, including the actual
reason field, expected reason, result type, and testing failure function.
Codegen evaluates the errable once, distinguishes unexpected success from a
reason mismatch, and merges both testing failures with the successful `ok`
result through explicit LLVM control flow. Testing failures now append a source
trace entry with a context naming unexpected success or the expected and actual
reason, selected from the runtime reason tag.

The minimal program now reaches codegen and reports an `InvalidType` at the
abstract `write_trace_text` parameter in `core/errors/errors.rg`. Restoring
abstract-parameter specialization and concrete backing storage is the shared
runtime prerequisite for positive executable validation. Do not treat the
internal test result as suite parity.

Checkpoint: 2026-09-09, branch `compact-semantic-graph-chatgpt`.
The session started at `6d90348`; the branch was fast-forwarded to the published
`97ac0c5` before implementation. The changes described below are local changes
on top of that commit. The refactor is **not ready to merge**.

## Changes in this checkpoint

- Infer implicit generic type parameters from current argument node types,
  including pointer children and named generic container arguments. Do not use
  the call aggregate's potentially stale field types as inference evidence.
- Reject conflicting repeated type parameters. Respect named/positional call
  arguments and module visibility during candidate lookup.
- Resolve nested template calls with the same overload selection and implicit
  inference used for ordinary deferred calls. Complete their call inputs.
- Score generic signatures before instantiating the selected body. Signature
  probes discard temporary graph entries; otherwise each fixed-point retry can
  introduce fresh generic identities and prevent termination.
- Roll back appended graph pools and instance statistics when generic body
  instantiation fails. Previously a reserved instance could survive with an
  incomplete body and be incorrectly reused on the next retry.
- Refine inferred local binding types from their instantiated initializers and
  use those types for binding-use nodes. Publish recursively instantiated nodes,
  bindings, blocks and bodies only after recursive work has completed.
- Permit a mutable pointer argument where a read-only pointer to the same child
  type is expected; reject the reverse permission change.
- Correct the ExternalRef size-budget test to 44 bytes, accounting for both
  optional qualifier and optional generic-argument ranges.
- Preserve abstract type identity through call compatibility and use abstract
  implementation checks when a concrete pointer is passed to an abstract
  parameter.
- Lower and instantiate template matches, contextual choice literals and
  empty type initializers. Resolve ordinary `is(.value = x, .variant = ..tag)`
  calls as tag comparisons so payload-bearing variants can be tested without
  constructing their payload.
- Materialize generic type fields before their bodies inspect those fields.
- Avoid caching requirement instances across speculative graph rollback;
  rolled-back IDs can otherwise alias unrelated types on the next fixed-point
  pass.

Implementation comments live beside the corresponding code in
`src/4_semantics/global_semantic_generic_functions.zig`.

## Validation

- `zig build` passes with local Zig 0.16.0.
- Latest internal tests: **110 passed, 1 crash, 111 total**. The remaining crash
  is the existing downstream LSP null-result assumption described below.
- Three new regression tests pass: nested implicit inference through a local
  pointer alias (including a discarded overload with an unresolved body),
  conflicting repeated parameters, and repeated failed instantiation without
  publishing a reusable partial instance.
- The existing LSP protocol definition test still crashes when it assumes the
  returned `result` is an object but receives null after semantizing fails.
- The final full-suite run was stopped after the internal results were available,
  at the user's request to end the session. The complete executable suite is not green. An earlier full run in this session
  reported 31 passed / 627 failed; it is not a clean final before/after comparison
  because compiler development overlapped that run. Do not present the internal
  count as the result of the whole suite.
- The minimal module still fails during semantizing, before codegen; no new
  executable or LLVM IR was validated for this checkpoint.

Reproduce using the current test path (the old `tests/00_minimal_main` path does
not exist):

```sh
env ZIG_LOCAL_CACHE_DIR=$PWD/.zig-cache ZIG_GLOBAL_CACHE_DIR=$PWD/.zig-global-cache zig build
./zig-out/bin/argi build tests/feature_tests/basics/01_minimal_main
env ZIG_LOCAL_CACHE_DIR=$PWD/.zig-cache ZIG_GLOBAL_CACHE_DIR=$PWD/.zig-global-cache zig build test
```

## Observed remaining blockers, in suggested order

GlobalSema now has an entrypoint-driven function closure. Pending operations
record their owning function; normal builds resolve only reachable body work,
while `check` retains exhaustive whole-module behavior. The closure follows
direct calls, type initializers, testing helpers and all implementations in a
virtual registry. Function interfaces remain global because overload dispatch
needs them before a body becomes reachable. Dormant body bindings have their
construction-only unresolved state retired before GlobalSG is published, and
their function bodies are removed from the final graph. This restores the old
selective-body algorithm at the GlobalSG boundary without moving cross-module
dispatch back into ModuleSema.

Error reason inference is again interprocedural. ModuleSG marks inferred
Errable signatures, and GlobalSema repeatedly derives effective reason sets
from returned values, output assignments and propagation nodes. Calls consume
the callee's previous summary, so recursive and transitive chains converge at
the whole-program fixed point. Inferred signatures update their identity-bearing
open choice; explicitly declared signatures retain a separate subset in
`Function.inferred_error_reasons`.

1. **Finish ordinary system initializers.** Allocator and strings now resolve
   completely. Trusted drops of a type without an explicit destructor lower to
   a no-op, matching the retired semantizer. Contextual structural literals
   participate in overload scoring, and deferred `move`/arithmetic nodes refine
   after their bindings become concrete. The next group is `core/system`:
   `size_of(.type = UIntNative)` still contains an unresolved type identifier in
   a value expression, and ordinary `CAllocator()`, `Terminal(...)`,
   `Arguments()` and related type initializers need the non-template
   initialization path.
2. **Complete virtual codegen.** All three allocator `to_virtual` calls now
   resolve by validating every abstract requirement and recording one concrete
   function per vtable slot. The semantic graph contains real method and safety
   registries. `src/5_codegen/global_codegen.zig` still returns
   `NotYetImplemented` for both `virtualize` and `virtual_call`; semantizing
   alone will not finish this.
3. **Core formatting correction.** `format_unsigned_decimal_into_u64` and
   `format_signed_decimal_into_i64` incorrectly called their 32-bit helper
   names. They now select the existing overloaded 64-bit helper, avoiding an
   unsafe implicit narrowing conversion in semantizing.
4. **Inference coverage.** This checkpoint handles type parameters, pointers,
   and named generic container arguments. It does not implement inference of
   comptime integers, dependent array lengths, or all other template type forms.
   Add focused positive/negative tests before extending those cases.
5. **Module-local generic materialization.** An attempted end-to-end fixture with
   a local `Box#(.t: Int32)` variable failed ModuleSG completeness verification
   with `IncompleteGenericMaterialization`, before GlobalSema. This independent
   issue was observed but not repaired; the retained inference fixture uses a
   scalar pointee to isolate the intended regression.
6. **LSP and diagnostics.** The definition test's null result is downstream of
   unresolved core semantizing. Merely avoiding the union access in the test
   would not restore definitions. Pending-call diagnostics currently print only
   the first eight unresolved operations and discard nested candidate failure
   reasons; preserve a useful selected-candidate cause and source location when
   improving this next.

Once the minimum passes, validate its LLVM IR and executable, then run the full
suite to distinguish shared-core failures from feature-specific regressions.
Do not merge to develop/main or claim refactor parity from internal tests alone.
