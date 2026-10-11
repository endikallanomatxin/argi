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

Keep unsupported relations conservative and require explicit contracts for
erasure. Before extending the vocabulary, identify a concrete core
operation that needs the additional precision. In particular, keep `Resizable`
statically dispatched until its hidden ownership transitions can be expressed;
adding dependency permissions alone would not describe insertion or removal.

Use [the precision study](safety_effect_precision.md) to guide the next effects
implementation. Its structural boundary retains individual discriminants and
nested payload paths, but conservatively forgets conjunctions of independent
discriminants and predicates over ordinary values.

- Extend guarded generation summaries to branch-assigned outputs and
  intermediate results, choice tests on computed expressions and error
  propagation. Direct forwarding, bound
  discrimination, moves and copies preserve call provenance; more complex
  flows must remain conservative without reviving expired roots.
- Extend `on output ..variant` to effects on other outputs.
  Use shared effect records rather than eagerly enumerating a Cartesian product
  of output variants. Distinguish effect permissions from required guarantees;
  common clauses apply to all outcomes and conditional clauses add obligations.
- Extend compatibility checking with initialization and outcome-specific hidden
  storage guarantees. Extend unconditional known-input retention and empty
  guarantees to grouped domains and mappings through reference fields. Extend known-input
  `consumes` to cleanup identities for erased receivers, indexed owners and
  mapped domains.
  Extend generation-only `invalidates` to checked aggregate/result facts after
  invalidation without dropping existing ownership or field facts.
- Extend mapped domain effects to exact ownership transfer and initialization.
  Broad dependency permissions must not become permission to transfer
  ownership, replace generations or manufacture safe references.
- Extend exact identity and ownership transfer proofs beyond straight-line
  lexical forwarding before admitting control flow or intermediate calls in `refers_to` and
  `transfers`. Preserve actual storage identities; do not represent every returned
  pointer as the receiver address. Mapped virtual results require proven input
  identity relations; extend output domain mappings before admitting arbitrary
  fresh or dependency-only handles.
- Extend declaration checking alongside further storage effect clauses,
  retaining diagnostics for implicit error-tracer inputs.
- Extend independence and conformance fixtures to conditional owner transfers,
  opaque storage,
  error outcomes and aliased inputs as their contract representation becomes
  available.

## Remaining storage transitions

Extend paired refinement beyond whole-value transfers only when post-values
can be represented without recovering old caller state.
Extend conditional consumption refinement to opaque effects and
replacement post-values without restoring caller snapshots.

Unconditional known-input retention and extraction preserve hidden provenance;
they do not guarantee which runtime slot is occupied or which value is extracted.
Extend exact hidden ownership transfer proofs before exposing those guarantees.
Single-storage receiver domains retain those effects through erasure. Extend
their identity representation before admitting grouped opaque storage or mappings
through references.
Represent returned hidden domains before discharging their conservative union
of possible input dependencies. Until then, owners and reference-containing
outputs retain those obligations even after a later empty-state guarantee.

Fresh initialization needs declared ownership and dependency roles for input
post-values, rather than treating an empty destination as permission to create
an arbitrary owner. Hidden storage still needs exact transfer, conditional
retention and
empty-state guarantees. Outcome-selected extraction provenance already follows
nested payload choices without implying those input transitions. Extend named
domains before supporting erased receiver
initialization or replacement; known layout at static dispatch must not be
required to interpret a virtual contract.
