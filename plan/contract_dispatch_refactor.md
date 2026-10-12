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

1. Migrate Writer next, including generic adapters and unary virtual evidence,
   then ErrorTracer and Allocator. Reader now uses selected scoped evidence
   throughout its bundled adapters and callers. Preserve fallible virtual capability
   inputs, storage acquisition proofs and cleanup. Unary receiver safety normalization
   recognizes the original participant parameter; preserve pointer-field dependencies
   and generation facts when migrating each adapter. Continue with the remaining
   bundled core/more operations, including BorrowedOrderPolicy.
   OrderPolicy, HashPolicy and BorrowedHashPolicy already use explicit participants
   and scoped implementations. Replace each implicit receiver contract with explicit
   participants and each global operation family with scoped implementations. Remove the superseded route as its final consumers move.
   Resolve unqualified calls by operation identity and participant inference.
   Replace temporary rejections of unqualified OrderPolicy.less and
   HashPolicy.hash and Reader.read_byte with scoped-identity assertions when that resolution is
   implemented.
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
