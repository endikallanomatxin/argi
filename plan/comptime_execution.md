# Bytecode execution

Release order: [0.4](0.4.md). Language semantics:
[compile-time execution](../description/50_comptime.md).

## Initial executor

The checked semantic graph feeds alternative backends under `src/5_codegen/`:
`llvm/` emits native code and `bytecode/` emits verified instructions. The VM
lives in `src/execution/`; execution is not a subsequent compilation phase.

`argi run --vm <directory>` lowers the checked global graph to typed bytecode
with source locations. VM initialization verifies signatures, control flow and
definite initialization once before execution of a bounded scalar/aggregate
subset. Function and type identities remain those of the retained global graph. See [usage](../docs/usage.md#experimental-bytecode-execution).

Next: resolve lifecycle transitions for runtime destinations, extend partial
initialization and error propagation, then build persistent sessions and stage compile-time evaluation.
Do not bypass safety to execute a larger subset.

REPL submissions and imported Argi functions use the same bytecode executor.
Reuse checked specializations and bytecode within a retained compilation session.
The bytecode lowerer now retains compiled functions across entry compilations
and publishes a separate immutable function table for each program. A rejected
dependency rolls back all new cache entries; retries cannot reuse a caller whose
closure failed to compile. Published tables keep sharing immutable function code
and the same finalized graph, which must outlive them. Appending definitions or
changing graph identities still requires a compilation-session boundary.
Relocation now appends module batches transactionally without changing retained
IDs; generic candidate indexes extend the retained module prefix. Semantic
resolvers now share one in-place context that owns their callback targets and
caches. Phase queues and dense operation status tables can append new modules
transactionally while preserving prior results; the same resolution state owns
finalized function identities and cumulative resolution progress. The fixed-point
executor advances without sealing construction metadata. The ordinary compiler
uses the retained semantic session's explicit initialization, advancement and
publication lifecycle. Contract registration tracks its source cursor and module
views can extend the immutable prefix; template indexes extend cached groups,
including empty ones. Import linking can append a module suffix transactionally
without retargeting retained aliases. The session can append a borrowed module
suffix and resume resolution, initializing only its external type slots; repeated
FFI preparation preserves already augmented signatures. Preparation failure
currently poisons this unpublished construction session. Independent copies of
semantic pools, pending/finalized operation state and staged execution requests
preserve IDs while isolating candidate edits, including request binding storage.
Resolver contexts copy retained call environments, cleanup effects and caches,
rebinding callbacks to candidate-owned targets. A quiescent semantic session can
fork without replaying source, append modules and reject or finish that candidate
independently. The execution compilation session checks independent publication
snapshots through ordinary safety analysis and compile-time evaluation before
accepting a revision. Stale candidates are rejected; accepted graph versions
retain stable addresses for existing bytecode. VM program instances can borrow
one execution context; storage identity, cumulative memory and terminal trap state
belong to that context, while invocation fuel belongs to each execution. Context
sharing adds no heap allocation to ordinary isolated VM construction. Next, add
source submission loading and lifecycle lowering of checked session bindings before wiring
interactive commands and conditional imports. Verified bytecode can initialize
and borrow graph-identified session bindings through typed layouts, sharing the
ordinary captured-write and cleanup protocol. A unique compilation namespace
separates graph-relative binding IDs across independent compilations. Concrete
storage can now create
session-lifetime regions independently of calls, copy their cleanup layouts and
initialize vacant slots without retaining temporary frame references. Region
retirement requires inactive cleanup flags. These low-level operations still need
the frontend's checked binding and cleanup-transfer plans.
JIT is deferred until measurements justify it; module origin is not an execution
policy. Keep function identities independent of the executor, without introducing
a mixed VM/native ABI or native-layout storage solely for a possible future JIT.

Calls use an explicit VM frame stack, with one shared instruction budget and a
configurable depth limit independent of the host call stack. `invoke` retains
execution storage and context identity, resets per-invocation fuel and shares the
cumulative allocation budget. Invalid entries/arguments publish no state; a trap
poisons the context until explicit reset. `run` remains a fresh-context convenience
API, and returned aggregates may be passed into its next call.

Local writes use a root slot plus typed field/index projections. Index operands
are evaluated once, and intermediate bounds checks retain native evaluation order.
Writes capture a typed destination before evaluating the RHS. These destinations
have a separate function-local register bank, cannot appear in language values
or cross calls, and retain concrete storage projections rather than rereading
reference/index operands at commit. Verification requires capture on every
incoming path; execution still checks liveness, access and aggregate bounds.
Capturing does not grant permission to initialize vacant storage. When a checked
write activates cleanup, capture also resolves the target's compiler-selected
flag entry before the RHS; commit activates that same subtree. This never uses
the flags of a slot that merely contains a reference, and flag updates consume
the shared execution budget.
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

## Lifecycle transitions

Storage owns concrete lifecycle state; reference values carry access to that
storage, not copies of its cleanup obligations. A checked replacement follows:

1. Capture the destination once while its backing storage is live.
2. Evaluate the RHS into a separate lexical owner. Failure leaves the old value.
3. Execute the frontend-selected cleanup against the destination's active subtree.
4. Commit the replacement and activate its cleanup, consuming the captured access.

Bytecode verification consumes destination registers after explicit activation,
and each loop iteration must recapture them. Runtime commit rejects any active flag in the
captured cleanup subtree, including live children under an inactive root. A
failed write does not reactivate flags. The executor explicitly orders cleanup
validation, value storage and flag activation. Storage.write changes only the
value; it never activates cleanup implicitly. Lowering emits separate cleanup
validation, store and activation instructions against one destination register.
Verification tracks captured, checked and written stages, requires the final
three instructions to be consecutive and consumes the register on activation.
Checks and updates count against fuel. Shared lifecycle lowering remains pending.
These checks validate execution of selected plans; they do not select destructors
or replace the safety proof. Fatal interruption still poisons a future persistent
session rather than promising rollback or replayable cleanup.

The checked graph represents a complete write as `replacement`. Its verified
plan identifies the destination write, prepared owner, selected cleanup and final
move together. Generic value sequences remain ordinary ordered expressions;
they no longer identify replacement. Safety and summaries traverse the ordinary
nodes inside the transition. LLVM and bytecode consume the same complete plan.
Native capture precedes preparation; cleanup and commit use that captured address
and flag range. Nested transitions restore the outer capture, independently of
temporary and scope-exit cleanup.

This remains local evidence. AOT must carry it through reference-valued fields,
arguments and outputs before using the plan for unknown targets. VM references
already preserve concrete storage identity across those boundaries.
The private Argi ABI now provides opt-in typed input evidence and caller-owned
output-evidence storage, independently of direct/indirect value returns. Its
shared signature validates both channels before emitting a call or return;
functions without evidence keep the existing ABI. Codegen does not request these
channels yet: reference propagation must supply the actual owner/projection
state first. C imports/exports and callbacks retain their separate ABI.

`reference_layout.zig` defines a separate, memoized layout for reference-valued
leaves, with semantic field/variant/index projections. Arrays use checked counts
without per-element expansion; reference recursion stops at the leaf. Native
companions pair the referent's cleanup-state pointer with its reference-evidence
storage pointer. Zero-reference values have no companion. The LLVM projection
and ABI transport are tested together, but ordinary expression emission does
not yet populate or propagate these companions. Virtual receivers remain an
explicit unsupported evidence shape rather than silently losing their state.

Native cleanup views are passed by value and refer to a shared type layout,
without a recursively allocated view tree per owner. Cached child offsets and
counts project ranges without allocating another view; cache growth preserves
existing views. Local allocation and incoming ABI flag pointers use the same
representation and subtree updates. Borrowing a view emits no flag allocation
or initialization. Ordinary reference expressions still need to populate and
forward the companion descriptors.

Do not generalize lexical body-pattern proofs to substitute for that evidence.
General owning indirect replacement remains unsupported until both backends and
the checker implement the transition. Explicit consume/write/consume through a
direct symbolic input now executes in bytecode: the checker retains a definite
initialization proof across every visited incoming state, calls retain symbolic
consumption targets, and lowering updates the referent's flags through evaluated
argument snapshots. Live-target replacement still requires its selected plan.
This does not yet support physically vacant output slots or partial aggregates.

Next acceptance case: call the same `store(target: $&Resource, ...)` with a live
owner and with storage explicitly vacated by `deinit`. Across both scopes this
must execute four destructors: two old values and two replacements. The native
probe currently executes three; VM lowering still rejects the unplanned owning
write in store. Transport and initialization must close this case together,
without imposing an initialized-only reference precondition or calling cleanup
unconditionally. This is the next milestone, ahead of further helper APIs.

Direct symbolic input references now separate backing validity from the observed
value generation. Explicit consumption ends the generation, and a subsequent
straight-line initialization renews only the selected access after evaluating
the RHS. Historical aliases remain stale; potentially aliased inputs are still
conservative. No concrete pointee or disjointness proof is invented.

Definite initialization summaries renew the selected symbolic argument slot
after calls, including reference fields in Args. Possible writes do not renew
it; copied records and accesses keep their old generations.

Unknown references inside by-value input records now receive separate dense
function-local identities, including nested records. Empty siblings retain empty
facts; the aggregate carries dependencies but no whole-pointer consumption
identity. Summary effects distinguish a reference field slot from its unknown
referent. Copies keep their observed generation; renewal changes only the
selected field. Arrays, choice payloads and contents behind unknown pointers
still need corresponding input facts.

Remaining: reconcile branch and loop generations, connect complete replacement
to native evidence and VM output initialization, and close the live/vacated
four-destructor acceptance case.

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
Bytecode lowering keeps cleanup in one preorder table with 32-bit handles and
subtree end indices. Projection follows those ranges without allocating a
parallel recursive DropState tree; finalization emits the runtime flag layout.
Variants without payloads have no entry.

Both backends share the field/variant layout of cleanup state. `cleanup_plan.zig`
resolves selected child types, variant identities and auxiliary arguments without
copying plans or allocating another IR. A shared outcome-path iterator validates
nested result selectors; backends emit guards before projecting each payload.
Selected cleanup traversal is also shared: one compile-time-specialized emitter
walks activation guards, nominal calls, fields, guarded variant payloads and final
deactivation. Each backend supplies only representation and instruction emission.
General replacement lowering and call-state updates still need integration.
Native evidence must retain owner/projection identity: zero-sized siblings can
share an address while retaining independent cleanup obligations.
Native flags use one preorder block per owner; each projected subtree has a
stable pointer and range. Native definitions, ordinary/virtual calls, generated
cleanup and trace helpers share one private ABI signature and call emitter;
C signatures remain target-specific. For transport, pass this companion where
lifecycle operations need it; never reconstruct it by comparing value addresses.

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
their copies. A checked body that only returns one of its reference inputs
preserves that identity, including concrete generic specializations. All inputs
and the single output must be references, so input cleanup cannot change the
proof during finalization. The original call still executes and retains its
ordinary safety effects. Defaults never substitute for actual arguments.
Mutable records and other function results do not establish that proof.
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

Function output defaults now normalize to declaration-ordered first writes in
an entry prologue before ownership finalization. Summaries, temporal checking,
once validation and both backends consume those ordinary assignments. Checked
functions retain no implicit initialization on output bindings. Tests cover
consumption in a generic output default followed by repeated destruction or
valid reinitialization; the former was previously accepted and aborted in the VM.
Concrete defaults lower inside the function scope, including ordinary inputs,
earlier outputs and lexical temporaries. They are not reusable field defaults.

## Persistent execution (proposed)

`Vm.run` currently resets its arena and frame numbering. Context identities
prevent references from resolving to unrelated slots in another run, even when
frame numbers coincide. Entry validation still rejects external references.
External session handles need non-reusable generations and checked publishing;
context identity alone does not establish cross-command validity. This does not
require generation checks on every internal VM reference. The retained compiler
environment proves language borrowing across commands; runtime handle validation
protects the session boundary rather than implementing a second safety checker.

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
`execution/evaluate.zig` now proves a closed function dependency unit with the
ordinary safety checker, then evaluates it through bytecode lowering and the VM.
It exports scalar/aggregate outputs as
compiler-owned graph literals. Input/output types with references or cleanup
are rejected before execution. Result validation precedes publication; export
failure rolls back appended nodes and value-field/reference tables. This boundary
is tested with a loop returning a record containing an array.

Source `#run` calls now retain explicit sparse requests through module caching,
global relocation and generic body specialization. After semantic/safety
completion, requests resolve their checked dependency units and replace their
call nodes with frozen constants. Nested requests use dependency order and cycle
detection, independent of declaration order. Runtime variables are rejected as
arguments, and aborted evaluation becomes a source diagnostic. AOT and VM tests
cover an aggregate returned through nested requests in a generic body. This
source connection now also feeds integer type/specialization arguments through
staged semantic resolution. Conditional declaration selection remains pending.

Closed calls and selected integer arithmetic/comparisons in arguments now use
ordinary VM execution too. Each explicit request shares one remaining instruction
and cumulative-storage budget across its implicit argument evaluations. Those
evaluations do not rewrite ordinary runtime source nodes. A separate bytecode
expression entry supplies typed operand slots without inventing a GlobalFunctionId;
it uses the same verifier, frame stack and retained-context rules. Owning entry
inputs/results remain rejected until submission lifetime/cleanup plans exist.
Field and array projections also use this entry path, including aggregate
results and ordinary VM bounds checks. General expression capture and staged
type formation remain pending.

Dependency units use the existing function/node/evidence traversal without
program roots. Summary inference and temporal checking share the same selected
unit; operation promises remain selected by identity, not by function name.
Output initializers participate in the closure alongside bodies, defaults and
cleanup. Tests establish that an unrelated body error does not block evaluation,
while an error in a dependency reached from an output initializer does. The unit
still requires finalized semantic dependencies; staged resolution and type
formation remain pending.

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

## Next integration steps

Integer argument requests now register bound recipes without retaining speculative
node IDs. GlobalSema materializes them between resolution passes, makes their
selected dependencies reachable, waits for those bodies' pending work and cleanup,
then uses the ordinary unit checker/evaluator to freeze the result. Completed
requests wake types and calls. Keys include bound integer/type parameters; type
identities created within an active speculative pass cannot be retained yet.

- Complete request dependency diagnostics and source-independent checking for
  callers of GlobalSema without a diagnostic source database.
Request registration participates in generic selection checkpoints. Rejected
selections discard their new recipes; suspension on a compile-time dependency
retains stable recipes while rolling back incomplete graph/evidence. Nested
selections remain subject to their enclosing transaction. Pending computation
must propagate through input/constraint probes rather than count as a mismatch.

- Support temporary type recipes without retaining IDs from rolled-back tails.
`conditional_source.zig` now indexes conditional source spans independently of
predicate evaluation. Its decisions are true/false/pending; a pending condition
hides both arms and exposes only the active unresolved frontier. Target selection
uses this same plan and retains its previous condition-validation behavior.

Computed function-body conditions now use staged checked execution, with separate
Bool requests and branch materialization per specialization. Concrete bodies retain
syntax-free IR until their conditions are ready, preserving their ordinary identity.

- Extend selection to module declarations and imports while retaining semantic
  session state. Discover imports only after their branch is selected.
- Extend closed condition expressions, preserving short-circuit evaluation.

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

Session places retain their storage region through projections. Bytecode lowering
can read and borrow selected session bindings and route non-owning whole writes
through captured destinations. Session drop metadata now routes selected cleanup and moves to persistent flags,
without emitting call-frame flags for the same storage; supplied layouts must
match the compiler's shape. Initialized session declarations now publish their value and activate persistent
cleanup directly rather than introducing a local owner. Deferred publication is
rejected until vacant binding plans exist. Owning session replacement and the
cross-command safety environment still require complete checked transfer plans.

Cross-command safety must retain the checker state and its immutable fact arena.
Branch clones share a validity-root namespace; independent submission candidates
copy that namespace and its initial-storage associations instead. Root IDs cannot
wrap into accepted identities. Retaining this namespace alone does not retain
loans: the complete temporal state still needs submission-level integration.
