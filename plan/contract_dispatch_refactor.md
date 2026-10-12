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

1. Extend participant pattern matching to nested nominal applications and named
   participant arguments. Extend comparison to remaining structural shapes;
   the current substitution handles type and integer parameter leaves, closed
   types, references, arrays and repeated-variable equalities. Keep arithmetic
   expressions conservative without introducing inverse constraint inference. Preserve the
   rejection of equivalent and incomparable maximal patterns.
   Check duplicate patterns and extension ownership even for dormant templates.
2. Validate newly instantiated evidence during resolution so nested operations
   and requirements reach the same fixed point as ordinary calls. Infer generic
   alias arguments from selected input signatures,
   without selecting by return type. Enforce extension ownership from nominal
   participant families; migrate generic constraints/composition without changing
   operation identities.
3. Resolve unqualified calls by operation identity and participant inference.
   Migrate bundled core/more operations and tests. Remove global overload lookup,
   legacy function declaration adapters, `satisfies` and `Abstract` compatibility.
   No long-term parallel overload mechanism is intended. Give editor references
   and rename actions operation targets distinct from their implementation bodies;
   current navigation follows bodies and rename is disabled for those targets.
4. Introduce standard Init, Convert, Deinit and operator contracts. Replace the
   old constructor/destructor/operator indexes with explicit operation identities,
   preserving resource initialization, cleanup and capability dependencies.
5. Route unary virtual construction through selected implementation evidence;
   support joint packages only with explicit representation and safety proofs.
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
