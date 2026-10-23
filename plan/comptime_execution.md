# Bytecode execution

Release order: [0.4](0.4.md). Supported commands/subset:
[usage](../docs/usage.md#experimental-bytecode-execution). Semantics:
[compile-time execution](../description/50_comptime.md).

## Memory and cleanup

- Support acquired aggregates containing resources and references. Connect the
  acquisition receipt, logical slot index, shared cleanup identity and native
  reference companions. Byte addresses cannot identify owners or zero-sized slots.
  Typed `allocate` retains element size and count, and zero-sized slot selection
  checks that logical bound. Connect explicit evidence reservation before enabling
  resource borrows, without allocation during borrowing.
  Native opaque writes already forward reference companions, but address-based
  establishment supplies none. Reserve companions and cleanup ranges together;
  borrowing must project that reservation rather than create it lazily.
  Lowering now carries verified receipt field descriptors and logical indices.
  Receipt bounds select a physical region, not a typed cleanup reservation.
  Executor reservations share layouts and dense per-batch buffers, separating
  occupancy from cleanup with allocation-free indexed borrowing. Connect them to
  lowering, native companions and nonnumeric storage; raw addresses cannot recover them.
- Represent construction of vacant choice payloads separately from discriminant
  presence and whole-value readiness. Incomplete records/choices must clean live
  children without invoking a whole-value destructor or reviving moved payloads.
  Contextual defaults now resolve for indexed/indirect writes and array elements,
  retaining ordinary lexical temporary storage and single destination evaluation.
- Complete evaluated identities for dynamic indices. Constant-index proofs and
  abstract repeated-element cleanup do not establish dynamic-index identity or
  disjointness. Keep symbolic storage sparse rather than expanding array lengths.
- Finish historical-observation widening in loops and integration of symbolic
  identities with opaque/acquired storage. Reuse of unretained observations already
  converges; retained aliases and guarded metadata must never become current again.
- Finish single-evaluation access handling and general retargeting through calls
  in summaries. Capture destination, evaluate RHS, clean old value, commit, activate.
  Preserve that capture across field/index projections and nested replacements.
- Broaden ordered consumption/observation validation across branches, loops,
  returned references, reference fields in Args, mapped domains and erased anchors.
  Independent participants remain usable; historical copies remain invalidated.
  Static bodies may add inferred obligations checked at concrete calls; virtual
  calls require the contract to express every obligation they impose.

## Compile-time integration

- Implement `#run (.system: System)` with checked host initialization and cleanup,
  sharing the VM/REPL execution host boundary. Keep capabilities explicit. Define
  host effects and build dependencies before enabling filesystem, stdin, networking,
  processes or unrestricted FFI.
- Extend temporary type recipes to inferred identities and transient declaration
  origins. Preserve nominal identity and defaults across speculative rollback;
  validate branch selection in native builds and retained sessions.
- Keep dependency readiness in the scheduler and execution in the VM. Preserve
  cycles, shared budgets, nested output restrictions and rejected-command rollback.

## Execution boundaries

- Finish eliminating semantic graph queries from execution. External arguments,
  scalar operations, storage projections, variants and host signatures already use
  prepared descriptors. Virtual compatibility still requires stable identities
  across semantic refinement: choosing the first equal type per snapshot is unsafe.
- Complete native reference-evidence production for acquired storage, arrays,
  choices, propagation, lifecycle wrappers and bulk copies. Checked reference
  offsets and readonly demotion now preserve existing companions, including
  zero-sized referents; they do not establish acquired companions. Bulk paths must carry
  destination companions before accepting reference aggregates. Reuse semantic
  plans, without a universal IR.
- Keep adapters on registered, signature-checked primitive identities; do not
  recognize user/core operations by incidental function names or paths.

## Scalability

- Reduce duplicated checked-graph prefixes and regenerated bodies while preserving
  stable identities, old virtual code units and rejected-command isolation.
  Recover temporary metadata/frames only after all live dependents release them.
- Continue measuring 10/100/1,000-command sessions, separating frontend, lowering,
  verification, execution and retained memory. Use `--graph-pools` for flat columns;
  account separately for nested metadata, safety proofs, bytecode and runtime storage.
- Current [measurements](../docs/usage.md#measuring-retained-execution): 100 resource
  commands retain 707 MiB with only 4,000 acquired bytes; graph payload is 418 MiB.
  Nonmoving trimming reduced column capacity from 626 to 425 MiB. Duplication
  remains. Minimal 1,000 updates retain about 436 MiB versus 19 MiB for definitions.
- Verifier linear-flow allocation has been reduced; joins still retain vectors
  proportional to joins times slots. Establish their cost in real workloads before
  changing representation. Do not optimize from synthetic measurements alone.

## Invariants and validation

- AOT, VM, REPL and compile-time share semantic/Safety decisions; the VM does not
  redo inference, borrowing, ownership or dispatch. JIT remains deferred.
- Publication is transactional; external execution effects cannot be rolled back.
  Traps poison execution until reset. Healthy reset/exit runs checked cleanup,
  including numbered expression results and retained resources.
- No evaluator reference, storage handle or temporary resource may escape as a
  compiler constant. Retained metadata must outlive all bytecode/values using it.
- Compare the same native/VM fixtures for partial initialization, moves, replacements,
  field/index cleanup, early exits, acquired resources and virtual dispatch. Include
  cross-command loans, rejected submissions, traps, reset and cancellation.
- Exercise `#run` and computed `#if` in native and retained sessions: defaults,
  inactive branches, cycles, allocation failures and rejected resource escapes.
- Confirm CI on Linux/macOS, x86_64/ARM64 for the latest execution changes; earlier
  green runs do not validate later commits.

## Later

- Separate host execution from target semantics for cross-compilation.
