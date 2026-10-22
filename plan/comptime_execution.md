# Bytecode execution

Release order: [0.4](0.4.md). Current commands and supported execution subset:
[usage](../docs/usage.md#experimental-bytecode-execution). Language semantics:
[compile-time execution](../description/50_comptime.md).

## Memory and lifecycle

- Complete acquired aggregate/resource storage and partial choice initialization.
  Acquired references currently preserve a byte range, not a logical slot.
  `MaybeUninit` reduces its index to `base + index * size`; zero-sized siblings
  therefore become indistinguishable before bytecode lowering. Preserve a
  checked slot receipt through allocation selection and reference establishment
  before attaching cleanup evidence. Do not key owner identity by byte address
  or create a fresh cleanup owner for each repeated reference conversion.
  Choice cleanup now separates discriminant presence from whole-value readiness:
  partial payload consumption skips nominal destruction and cleans live siblings.
  Reinitialization restores complete cleanup through shared ancestor flags;
  native/VM fixture 161 and retained-session exit cover this behavior. Vacant
  payload construction still needs its own initialization representation.
  Share identity, projections, initialization and validity rules with ordinary
  storage without requiring identical physical representations.
- Complete indexed cleanup identities in both backends. Whole indirect pointer
  and record-field replacements use checked plans, including the three-drop
  retargeting probe and preservation of sibling references in native and VM.
  Nested indirect fields and field reinitialization after destruction have
  differential coverage, including whole-record replacement after consuming a
  field through a function. The live-sibling structural fallback also passes
  in native and VM. Finish conditional caller cleanup activation.
  Incomplete records must never invoke a whole-value destructor.
  Preserve capture, RHS evaluation, old cleanup, commit and activation.
- Validate projected symbolic storage identities across aliases, branches, loops
  and session forks. Constant array indices now use lazily interned element
  identities in access and summary substitution; bounds and element types are
  checked without expanding the array length. Dynamic indices still need an
  evaluated index identity and cannot use the constant-index proof.
  First initialization after field destruction must preserve
  old-alias invalidation, run RHS effects before omitting old-value cleanup, and
  reactivate any existing runtime flags. Complete acquired resource evidence for
  replacements that still need to destroy a previous value; never infer it from
  a physical address or disable missing-evidence checks.
- Finish broad validation of ordered consumption/observation summary obligations.
  Calls check actual destinations; independent participants remain usable, while
  aliases retain ended incarnations after reinitialization. Cover branch/loop
  composition, returned references, reference fields within Args, mapped domains
  and validity-only erased anchors. Static selections retain inferred alias
  obligations for concrete call checking while preserving contract guarantees;
  virtual contracts reject unrepresented alias obligations. Keep the independent, aliased and read-before-consumption cases
  distinct; do not replace these obligations with group-wide invalidation.
- Complete single-evaluation access handling in the checker. Field/index reads
  and field/index/dereference/payload address formation capture pointer-producing calls once;
  the separate symbolic-address reevaluation walk has been removed. Extend this
  to remaining projections and syntax-based Place queries; preserve evaluated
  pointer facts rather than suppressing diagnostics.
  Field/array stores commit checker facts to the captured referent after RHS
  evaluation, even when that RHS retargets the reference used to select it.
  Payload reads and addresses reuse their evaluated choice access and active-tag
  proof. Regressions distinguish one operand move from an explicitly repeated
  evaluation for concrete and unknown referents; symbolic field and variant
  projections retain distinct identities. Typed payload projections preserve
  their types through lazy branch materialization and joins; payloadless variants
  do not establish storage identities. Case 151 compares payload borrowing
  and mutation after an effectful reference-returning call in native and VM.
  The returned-reference internal test covers independent and aliased operands,
  including VM execution of accepted field and array projections;
  case 148 retains the nested-call alias regression.

## Compile-time integration

- Complete `#run (.system: System)` with checked host-resource initialization
  and cleanup, sharing the execution host boundary with VM programs and the REPL.
  Keep capabilities explicit; define host effects and build dependencies before
  enabling filesystem, stdin, networking, processes or unrestricted FFI.
- Extend temporary type recipes beyond captured defaults to inferred identities
  and transient declaration origins; validate branch selection in native and
  retained sessions.
- Keep dependency readiness in the scheduler and execution in the VM. Preserve
  cycle checks, shared execution budgets and rejected-session rollback. Nested
  entries share the enclosing execution but retain their output restrictions.

## Execution boundaries

- Lower semantic decisions into explicit runtime descriptors for layout,
  references, variants, memory operations and selected dispatch.
  Numeric byte-view instructions now carry verified permission and endianness
  alongside their physical layout; execution no longer reads those decisions
  from slot types or the semantic target. Ordinary value/storage borrows also
  carry verified access permissions. Choice construction, payload extraction,
  tests and branches carry verified representation ordinals, retaining semantic
  IDs only for verification. Arithmetic/comparison instructions carry a compact
  verified scalar interpretation (width/sign or floating precision). Value-array
  indices also carry that interpretation; reference offsets have a verified
  UIntNative input and use its unsigned bits directly. Loads carry their erased
  anchor or signed/unsigned byte interpretation. Host scalar encoding reuses
  the selected binding's checked ranges. Storage paths carry verified variant
  ordinals and scalar index kinds; execution follows them without graph traversal.
  Host signatures are lowered to verified symbol/range descriptors; execution
  links them without consulting semantic fields or types.
- Replace core adapter name/path recognition with explicit primitive identities.
- Complete native value-evidence production for arrays, choices, error propagation
  and lifecycle wrappers. Ordinary and virtual call inputs/results carry the
  private channels; bulk-copy paths must transport destination companions before
  they can handle reference aggregates.
- Share semantic plans with native lowering; do not introduce a universal IR.
- Connect cooperative cancellation to CLI controls and complete trace reporting.

## Scalability

- Use `benchmark-execution` to compare 10, 100 and 1,000 submissions.
  [Measurements](../docs/usage.md#measuring-retained-execution): after module-prefix
  sharing and geometric source indexes, 1,000 minimal updates retain about
  713 MiB. Reduce duplicated checked graphs and code-unit metadata while
  preserving identities, branches and rejected-command isolation.
- Account for semantic snapshots/safety proofs, regenerated bytecode, retained
  code metadata and completed frames. Check whether time/memory grows quadratically.
  Verifier linear-flow states now transfer ownership between instructions; a
  1,000-slot synthetic function requests 26,421 bytes instead of 2,019,413.
  Joins retain their incoming states and intersection semantics. The isolated
  `--verifier` benchmark measures 1,000 diamonds/slots at 3,342,561 requested
  bytes and 2,077,429 peak bytes, with zero retained bytes; full join vectors
  still scale with joins times slots. Establish the importance of this cost in
  real programs before changing representation. These samples do not bound all
  CFG shapes.
- Use measurements to guide immutable sharing, stable identities, code reuse and
  temporary storage reclamation. Never reclaim metadata or resources still used
  by live references. JIT remains deferred.

## Later

- Separate host execution from target semantics for cross-compilation.

## Invariants

- VM execution and compile-time execution consume checked language semantics;
  neither reimplements dispatch, borrowing or ownership inference.
- Source/semantic publication is transactional. Executed effects cannot be rolled
  back; traps poison execution until reset.
- Session values, including numbered expression results, retain ordinary loans
  and cleanup. Healthy reset/exit executes checked cleanup before releasing them.
- Evaluator storage, references and native handles cannot escape as constants.
  Target widths/layouts must match supported execution semantics.
- Keep graph identities stable across submissions. Retained metadata must outlive
  bytecode and values that reference it; rejected candidates publish nothing.

## Validation

Run differential bytecode/AOT fixtures in CI on this branch for each added capability. Exercise cross-command loans,
partial moves, reinitialization without alias revival, owning expression results,
cleanup, rejected submissions, traps and reset. Test `#run` and computed `#if`
through retained sessions as well as native compilation, including inactive
branches, cycles, allocation failures and rejected evaluator-resource escapes.

Recheck published CI after the latest lifecycle changes. Run
[39678224716](https://github.com/endikallanomatxin/argi/actions/runs/39678224716)
passed at `2896cd99` on Linux and macOS, both x86_64 and ARM64. Subsequent
structural cleanup, indexed replacement and partial owning-array changes have
local validation but are not covered by that run.
