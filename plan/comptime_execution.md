# Bytecode execution

Release order: [0.4](0.4.md). Supported commands/subset:
[usage](../docs/usage.md#experimental-bytecode-execution). Semantics:
[compile-time execution](../description/50_comptime.md).

## Memory and cleanup

- Extend prepared acquired slots to choices. Typed `allocate`
  reserves companion ranges in the same acquisition and transports a private handle through `Allocation`.
  LLVM and bytecode share geometry; resource initialization, extraction,
  reuse and zero-sized slots use independent per-receipt identities. Records
  and arrays retain safe references and virtual receiver/witness pairs separately
  from numeric bytes; physical writes revoke affected evidence without invalidating
  neighboring elements.
  Borrowing projects a reservation without allocating metadata or recovering owners from
  data addresses. Raw/inherited storage with resources or stored references still
  needs explicit preparation.
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
- Extend temporary type recipes to inferred choice identities and transient
  declaration origins. Pending Errable wrappers retain their value types and
  unresolved reasons through rollback. Preserve nominal identity and defaults;
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

- Remove the temporary evaluation node-column copy; keep cleanup projection
  identities bounded when rechecking previously completed bodies.
- Reuse verified Safety bodies only with stable hypotheses; check caller facts
  independently. Reuse immutable helper bytecode across commands while keeping
  host bindings, globals and virtual dispatch linked to its originating Code Unit.
- Keep definition lookup separate from instantiation evidence. Delayed body
  completion must preserve its selected context; new conformances must not
  invalidate safety assumptions of published code.
- Recover temporary metadata/frames only after all live dependents release them;
  preserve cross-unit virtual dispatch, references, cleanup and reset.
- Continue measuring 10/100/1,000-command sessions, separating frontend, lowering,
  verification, execution and retained memory. Use `--graph-pools` for flat columns;
  account separately for nested metadata, safety proofs, bytecode and runtime storage.
- Baseline [measurements](../docs/usage.md#measuring-retained-execution): 100 resource
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
