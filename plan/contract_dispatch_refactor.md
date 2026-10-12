# Contract-scoped dispatch refactor

## Accepted model

Ordinary functions have one identity per module namespace, including all their
compile-time parameter shapes. Contracts own operation identities. `implement`
provides operations and associated elements for a participant tuple; only those
conformances participate in multiple dispatch. Participants come from inputs or
explicit compile-time arguments, never the expected return type. Resolve an
operation identity before ranking conformances. Resolve associated signatures
after selecting the conformance; incompatible calls do not fall back.

Qualified operations use `Contract#(participants).operation(...)`. Unqualified
calls require one applicable identity, including ordinary functions. Composition
retains dependency operation identities. External implementations belong to the
contract module or a nominal participant's module. Equivalent patterns and
incomparable maximal candidates are errors; source/import ordering has no priority.

## Implementation order and removal obligations

1. Continue migration with the remaining bundled operations. Iterator, Iterable,
   ROPointerIterable, RWPointerIterable and OwningIterable now select scoped
   implementations, including concrete/parameterized for lowering and owning
   iterator cleanup. Manual generic iteration and mutable-to-readonly operation
   input adaptation share the same operation resolver. Allocator,
   Deallocator, ErrorTracer, Reader and Writer use selected scoped evidence
   throughout their bundled adapters and callers. BlockReader and BlockWriter
   now share their static/virtual algorithms; StreamTransfer scopes endpoint
   specialization, and BorrowedOrderPolicy scopes owning comparisons. Preserve fallible
   virtual capability inputs, storage acquisition proofs and cleanup. Unary receiver
   safety normalization recognizes the original participant parameter; preserve
   pointer-field dependencies
   and generation facts when migrating each adapter. Continue with the remaining
   bundled core/more operations, including copying and argument sources.
   Indexable, IndexableMutable and IndexableValue now use selected Item evidence,
   with dependency identities rather than copied requirements. Resizable selects
   collection/allocation-provider tuples for growth; Removable selects only the
   collection for pop/remove. Named associated restrictions compare against the
   selected evidence and infer ordinary generic leaves. Newly selected evidence
   participates in the resolution/cleanup fixed point.
   OrderPolicy, HashPolicy and BorrowedHashPolicy already use explicit participants
   and scoped implementations. Replace each implicit receiver contract with explicit
   participants and each global operation family with scoped implementations. Remove
   the superseded route as its final consumers move.
   Extend operation input inference to nested associated patterns and reached
   adaptation of by-value bindings. Lexical reach defaults now infer direct
   participants and field paths, including unary virtual receivers. Conformance
   ambiguity diagnostics survive probes.
   Current direct participant inference shares identity selection between
   concrete/generic bodies and compares ordinary generic applicability without
   instantiating its body. Explicit qualified calls remain the escape hatch.
   Remove global overload lookup, legacy function declaration adapters,
   `satisfies` and `Abstract` compatibility once their consumers are migrated.
   No long-term parallel overload mechanism is intended.
2. Add named participant arguments and extend symbolic comparison to remaining
   shapes as needed by these migrations. Current substitution handles type and
   integer parameter leaves, closed types, references, arrays, nominal applications
   with positional/named arguments and repeated-variable equalities. Keep
   arithmetic expressions conservative without inverse inference. Preserve rejection of equivalent and
   incomparable maximal patterns. Check duplicate patterns and extension ownership
   even for dormant templates.
3. Validate newly instantiated evidence during resolution so nested operations
   and requirements reach the same fixed point as ordinary calls. Infer generic
   alias arguments from selected inputs without selecting by return type.
   Preserve extension ownership and composition operation identities. Give editor
   references and rename actions operation targets distinct from implementation
   bodies; current navigation follows bodies and rename is disabled for them.
4. Introduce standard Init, Convert, Deinit and operator contracts. Replace the
   old constructor/destructor/operator indexes with explicit operation identities,
   preserving resource initialization, cleanup and capability dependencies.
5. Extend unary selected virtual evidence to associated parameters and storage
   domains; the unbound unary case already uses scoped implementations. Support
   joint packages only with explicit representation and safety proofs.
   Remove the remaining compatibility registry adapters and internal Abstract names.

Each step must leave persisted frontend graphs, speculative rollback, dormant
operation validation and safety proofs consistent. Do not disable safety checks
or introduce implicit allocation/copying to simplify the migration. Transitional
source support is allowed only while its callers are being migrated; list its
removal obligation here instead of designing a second permanent subsystem.

## Validation

Add executable and rejection fixtures under the existing contract category.
Keep coverage of module identity conflicts across files, generic-arity conflicts, same-named
operations in separate contracts, missing/duplicate/incompatible implementation
members, alias reuse, associated results, visibility and safety. Verify cold/warm
frontend behavior and emitted direct-call LLVM. Run focused checks with normal
parallel workers, then one full regression after implementation stabilizes.

TODO: preserve contextual fixed-array initialization inside parameterized ordinary
function bodies. A local `[1]UInt8 = (0)` currently makes specialization report an
incorrect generic-input mismatch; concrete bodies accept it. Keep this independent
from virtual participant evidence and improve the body diagnostic before removing
legacy ordinary resolution.

## Execution record

- Ruling: retain one operation identity for readonly indexing; mutable/value
  contracts require Indexable with equal Item evidence rather than repeating
  length/get_ro_ref. This preserves dependency namespaces. If incorrect, callers
  needing an independently specialized readonly implementation must declare a
  different capability explicitly.
- Ruling: Resizable selects Collection and Provider for allocating growth;
  Removable selects Collection alone for pop/remove. Allocation-free operations
  cannot infer a Provider participant. If incorrect, protocol names need revision,
  but ownership and allocation dependencies remain explicit.
- Selected evidence validation joins the ordinary resolution/cleanup fixed point;
  newly selected dependencies are validated in the same pass. Negative spatial
  fixtures exposed previously unvalidated operation tables during this migration.
