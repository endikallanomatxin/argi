# Bytecode execution

Release order: [0.4](0.4.md). Language semantics:
[compile-time execution](../description/50_comptime.md).

## Initial executor

The checked semantic graph feeds alternative backends under `src/5_codegen/`:
`llvm/` emits native code and `bytecode/` emits verified instructions. The VM
lives in `src/execution/`; execution is not a subsequent compilation phase.

`argi run --vm <directory>` lowers the checked global graph to typed bytecode
with source locations, verifies signatures/control flow/definite initialization,
and executes a bounded scalar/aggregate subset. Function and type identities remain
those of the retained global graph. See [usage](../docs/usage.md#experimental-bytecode-execution).

Next: resolve lifecycle transitions for runtime destinations, extend partial
initialization and error propagation, then build persistent sessions and `#run`.
Do not bypass safety to execute a larger subset.

REPL submissions and imported Argi functions use the same bytecode executor.
Reuse checked specializations and bytecode within a retained compilation session.
JIT is deferred until measurements justify it; module origin is not an execution
policy. Keep function identities independent of the executor, without introducing
a mixed VM/native ABI or native-layout storage solely for a possible future JIT.

Calls use an explicit VM frame stack, with one shared instruction budget and a
configurable depth limit independent of the host call stack. Each run resets its
execution state; returned aggregate values may be passed into the next run.

Local writes use a root slot plus typed field/index projections. Index operands
are evaluated once, and intermediate bounds checks retain native evaluation order.
The interpreter rebuilds only the modified aggregate path; immutable snapshots
preserve value-copy semantics. Safe references name an execution context, frame,
root slot and captured projections. Context identities are never reused across
runs. Slots explicitly distinguish vacant storage from complete values, including
Void; ordinary reference writes require initialized storage. The storage engine
rejects foreign contexts, dead frames and readonly writes; the ordinary frontend
continues to prove lexical lifetimes, aliasing, and storage-generation rules.
References cannot enter from external values or escape completed frames.

Cleanup lowers the frontend's selected operations and activation annotations to
ordinary branches and calls. Compiler-defined field/variant layouts attach flags
to actual frame storage. Frames initialize those flags independently of value
occupancy; moves disable source subtrees and initialization enables them.
Active payload guards precede their cleanup. Result-dependent consumption follows
selected output tags, including discarded results. No second ownership analysis
runs in the VM. Partial initialization through output references and native resources
remain outside the executor subset. Abort/quota failures do not execute user cleanup.

## Storage direction (proposed)

The reference-replacement investigation found a shared frontend gap, not only
an interpreter limitation. A native destructor-count probe for replacement
through `$&Resource` observed one cleanup instead of two. Bytecode lowering now
rejects that shape; it must not be enabled by assuming the destination is always
initialized. The corresponding boundary fixture is
[`25_owning_reference_vm_boundary`](../tests/feature_tests/execution/25_owning_reference_vm_boundary/main.rg).

Keep three representations of the same lifecycle rules:

| Layer | State |
| --- | --- |
| Safety analysis | Symbolic targets, possible aliases, generations, initialization and cleanup obligations; joins retain conservative facts. |
| Checked graph and summaries | Ordered transitions and caller-relative effects, including the access renewed by initialization. |
| Execution | Actual storage and the initialization/cleanup state that could not be eliminated statically. |

Do not move the entire checker into runtime or create one mutable state shared
by compilation and execution. Existing `Place`, `StorageGeneration`,
`SymbolicPointeeState`, and cleanup activation cover parts of this model. Extend
and reconcile them rather than adding another ownership registry. Runtime slot
occupancy now distinguishes vacancy from a complete value. Partial aggregate
initialization and value-generation transitions still need checked operations;
a complete-slot occupancy marker does not provide either.

Bytecode lifecycle instructions now resolve cleanup state through actual storage
identities, including references into caller frames, without reading vacant
values. They use the compiler's existing cleanup flags and sorted layouts, not
a second ownership analysis. General indirect replacement still requires checked
cleanup plans and corresponding native evidence transport before it is enabled.
Both backends share the field/variant layout of cleanup state. Native evidence
must retain owner/projection identity: zero-sized siblings can share an address
while retaining independent cleanup obligations.
Native flags use one preorder block per owner; each projected subtree has a
stable pointer and range. For transport, pass this companion where lifecycle
operations need it; never reconstruct it by comparing value addresses.

A reference needs a target identity and its observed generation. Aliases can
name the same target while retaining different observed generations. Shared
borrow dependencies express possible aliasing; they are not the target's own
identity. Conversely, assigning separate symbolic identities to two parameters
must not assert that they cannot alias. Summaries must preserve the resulting
alias requirements and generation effects at the caller.

Keep storage lifetime separate from its current value's lifetime. Replacement
captures a writable destination once, evaluates the RHS, accounts for the old
value, and initializes the new one. That destination access must survive the
value transition while its backing storage remains valid; it cannot survive
release of the backing storage. It is an internal checked operation, not a
public way to manufacture references to vacant slots.

Preserve the existing rule: the access used for reinitialization can follow its
new generation; sibling aliases stay stale. Ordinary writes without destruction
preserve existing aliases. Field replacement must preserve unrelated siblings.
Constant local aliases now carry their proven lexical cleanup target on writes;
both backends preserve the original pointer evaluation and use the target's flags.
This includes reference fields projected from immutable literal records and
their copies; mutable records and function results do not establish that proof.
Retargetable aliases and unknown input referents still need selected indirect
cleanup plans and native evidence transport.
Call summaries now distinguish preserved, possible and definite initialization;
caller cleanup reactivation follows actual writes and represented result outcomes.
An initialized post-state alone does not prove a value was written to vacant storage.
Do not infer cleanup from the slot containing a reference. Occupancy in opaque
collections remains owner-controlled, possibly through a length invariant,
rather than requiring a universal per-element flag table.

The checked graph should make initialization, mutation, movement, replacement,
and destruction distinguishable. Backends may lower these transitions to plain
stores, calls and flags; that information is currently lost if every write is
just a `store`. Define how necessary cleanup state crosses ordinary calls,
including generic specializations. A universal fat-reference ABI is not a
prerequisite established by this investigation.

## Persistent execution (proposed)

`Vm.run` currently resets its arena and frame numbering. Context identities
prevent references from resolving to unrelated slots in another run, even when
frame numbers coincide. Entry validation still rejects external references.
Persistent handles also need non-reusable value generations and checked
publishing; context identity alone does not establish cross-command validity.

Separate session bindings, command temporaries and call frames. Session bindings
must have session lifetime from their creation, not become escaped function
locals after a command returns. Retain the checked safety environment between
commands; keeping only the concrete values loses borrowing and cleanup facts.
Publishing an owner must move its cleanup obligation, not clone a raw `Value`.

Retain the type, selected cleanup evidence, source metadata and executable unit
needed by every live binding. `GlobalTypeId` and `GlobalFunctionId` are currently
graph-relative; they cannot identify definitions across independently rebuilt
graphs. Keep referenced versions alive and initially reject incompatible
redefinitions. Reset invalidates all old session handles.

Compilation rejection must publish no changes. An ordinary `Errable` follows
checked control flow and cleanup, but does not undo earlier writes or I/O.
Abort, quota exhaustion or cancellation at arbitrary instructions are different:
they can interrupt replacement or a destructor. State tracking alone cannot
make replaying cleanup safe. Initially poison the execution context after such
a trap and require reset; specify stronger recovery before enabling it. With
native resources, process isolation is an option for containing fatal failures,
not a promise to undo external effects or run language destructors.

## Comptime boundary (proposed)

Use a private evaluation context with explicit capabilities and budgets. A
successful result crosses a freeze boundary into compiler-owned constants;
evaluator storage, live resource owners and native handles do not cross it.
Start with representable scalar/aggregate constants without references. Later
support for immutable referenced data requires relocation and validation of the
whole constant graph, not retention of an evaluator arena. Type values likewise
need compiler-owned identities rather than evaluator addresses.

`#run` can be needed while types and specializations are being determined. It
cannot depend on completion of the entire global graph, as `run --vm` currently
does. Lower a closed, checked dependency unit and diagnose evaluation cycles.
Retain the same safety and target semantics; comptime execution does not inherit
runtime System/FFI capabilities or implicitly turn REPL values into constants.
Cache frozen results against checked code/evidence versions, target, explicit
inputs and declared external reads, never evaluator storage IDs or native
addresses.

## Remaining decisions

- Extend storage to partial initialization and error propagation.
- Bytecode call output storage, initialization, errors, and cleanup.
- Explicit host-call capabilities and supported signatures, when needed.
- Session persistence, redefinition, failed submissions, reset, and exit.
- Comptime capabilities, frozen results, target behavior, and cache dependencies.
- Instruction/recursion, memory, and time limits; cancellation at safe points.

## Constraints

Lower checked semantics; do not reimplement language resolution in the evaluator.
Keep function identity independent of its executor. Retained bytecode and its
type/evidence metadata must outlive their uses, including across redefinition
and failed submissions.

Rejected submissions must not publish partial definitions. Executed I/O cannot
be rolled back. Retained values need session-owned storage and ordinary lifetime
checks; initially reject redefinitions that invalidate live dependencies.

Comptime must not inherit runtime System/FFI permissions. Freeze supported values
into compiler-owned constants; reject escaped evaluator references/native handles.
Host execution must preserve target widths/layouts or reject unsupported operations.

## Validation

Compare VM and AOT for aggregates, generics, virtual calls,
errors, cleanup, and output lifetimes. Include aliased/disjoint reference inputs,
reinitialization without alias revival, partial moves, RHS destination changes,
and failed growth preserving old references. Session tests must cover cross-command
borrows, reset, definition retention, and traps during cleanup. Comptime tests
must reject evaluator-address/resource escapes and exercise target-dependent
results. Force executor modes in tests. Measure cold/repeated evaluation and
retained session memory; reconsider JIT only with evidence of a useful workload.

## Reference

Zig's `Sema.zig` evaluates comptime bodies during semantic analysis, with
explicit comptime allocations and an evaluation branch quota. The local study
uses the checksum-verified source archive for
[0.18.0-dev.253+16d31ceed](https://ziglang.org/builds/zig-0.18.0-dev.253+16d31ceed.tar.xz)
under ignored `references/zig/`. Argi keeps its planned reusable executor
separate from contract resolution; this is not Zig's execution architecture.
