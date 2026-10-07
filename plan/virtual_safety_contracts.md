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

- Extend compatibility checking with domain invalidation, allowed dependency
  storage, initialization/consumption and outcome-specific guarantees. Validate
  every provenance category, including fresh root identity and ownership roles.
- Define type-aware normalization and domain mapping before erasing receiver
  layouts. Broad dependency permissions must not become permission to transfer
  ownership, replace generations or manufacture safe references.
- Extend contract-generated virtual call summaries to reference and owner results.
  Scalar, no-result and exact input-reference forwarding contracts already have
  independent call summaries. Extend must-alias proofs beyond direct forwarding
  bodies before admitting control flow or intermediate calls in `refers_to`.
  Conservatively summarize permitted dependencies while preserving output
  structure and actual storage
  identities. Do not represent every returned pointer as the receiver address.
- Extend declaration checking to static abstract implementation selection and to
  the new effect clauses, retaining diagnostics for implicit error-tracer inputs.
- Describe and migrate Allocator, Deallocator, Reader, Writer and ErrorTracer.
  Keep the existing dispatch checker active until their complete obligations can
  be expressed; do not silently weaken checks during migration.
- Extend independence and conformance fixtures to nested owners, opaque storage,
  error outcomes and aliased inputs as their contract representation becomes
  available.
- Remove remaining program-wide summary unions after the core protocols migrate.
