# Abstract safety contracts

## Model

Abstract methods publish validity and storage obligations. Each implementation
must satisfy those obligations independently; unknown virtual dispatch uses the
published contract rather than the union of program-wide implementations.
Concrete calls retain their inferred summaries.

`depends_on` describes permitted output validity dependencies, recursively through
fields, choices, virtual receivers and opaque values. It grants neither ownership
nor an extended lifetime. A contract cannot authorize local storage escapes.
Receiver paths refer to the concrete referent, not the local input slot.

Reference mutability remains expressed by `&` and `$&`. By-value arguments may
contain references or capabilities, so their signatures do not establish purity.
Changing contents is distinct from ending or replacing a storage generation.

Named validity domains hide concrete storage paths. Domain mappings must preserve
actual generation identities at virtual conversion and across method calls;
domains do not acquire resources or prolong their lifetime. Output dependency
permissions and ownership transfers are separate obligations.

## Remaining work

- Extend compatibility checking with allowed dependency storage,
  initialization/consumption and outcome-specific storage guarantees.
  Source-level `invalidates` covers scalar reference inputs on no-result methods
  and mapped receiver domains. Extend it to checked aggregate/result
  facts after invalidation without dropping existing ownership or field facts.
- Extend mapped domain effects to owned and opaque storage transitions.
  Broad dependency permissions must not become permission to transfer
  ownership, replace generations or manufacture safe references.
- Extend must-alias and ownership transfer proofs beyond direct forwarding
  bodies before admitting control flow or intermediate calls in `refers_to` and
  `transfers`. Preserve actual storage identities; do not represent every returned
  pointer as the receiver address. Mapped virtual results require proven input
  identity relations; extend output domain mappings before admitting arbitrary
  fresh or dependency-only handles.
- Extend declaration checking to the new storage effect clauses, retaining
  diagnostics for implicit error-tracer inputs.
- Extend opaque storage and conditional generation obligations when protocols
  need to expose those effects. Keep unsupported effects rejected rather than
  inferring them from the program's implementation set.
- Extend independence and conformance fixtures to nested owners, opaque storage,
  error outcomes and aliased inputs as their contract representation becomes
  available.
