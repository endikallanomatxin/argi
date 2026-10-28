# Compiler follow-ups

Prioritize concrete consumers and measured costs. Keep completed test organization
and nominal-type migration closed; preserve their validation.

## Resolution and transactions

- Reduce persistent resolver scratch and diagnostic state. Keep candidate
  speculation distinct from session transactions; avoid replacing existing
  coordination with another layer of callbacks.
- Make pass prerequisites and produced facts explicit. Review ownership operand
  staging against shared lowering, preserving evaluation and cleanup exactly once.
- Reduce repeated resolution/completion/verifier work where profiles justify it.
  Typed-literal and write contextualization are stronger targets than initializer
  inference. Preserve pass order, old entities completed by new information and
  nested aggregate completion; an outer type is not a completion certificate.
- Measure invariant work in generic specialization before sharing representation.
- Unify collection-length lookup before extending CLI relationships. Iterating
  an `ArrayView#(CliSpec)` from an ordinary helper can select the constrained
  ordinary `length` and reject missing `CollectionLength`, although `Indexable`
  supplies `length`. A blanket adapter makes existing core calls ambiguous.
  Resolve the operation-identity boundary; do not bypass iteration with private
  layout access. Reproduce with `CliSpec` containing borrowed option-name lists.

## Safety

- Centralize state transitions when this removes coordinated mutations or duplicate
  rules. Keep graph reconstruction and loop widening in the checker; preserve
  slot/referent boundaries and stale-alias invalidity.
- Review declaration-side outcome translation against inferred effects, payload
  permissions, input guarantees and domain normalization. Compact output
  partitions still serve cleanup, forwarding and unreachable outcomes.
- Extend conditional generation, consumption, relocation and cleanup for concrete
  consumers. Preserve exact caller storage identities; permissions alone do not
  establish ownership or occupancy.
- Carry conditional whole-storage transitions through stored results, indirect
  outputs and loops rewriting discriminants. Retain intervening writes and
  cleanup; never restore an older caller snapshot when a tag is tested.
- Extend conditional hidden retention/replacement, grouped opaque mappings and
  selectors through arbitrary output fields when needed.
- Support erased receiver transitions only with represented storage and cleanup
  identities. Keep Resizable static until its hidden transitions are expressible.

## Execution

- Record external compile-time reads as reproducible build dependencies before
  exposing those host capabilities; include them in cache identity.
- Separate host execution from target semantics for cross-compilation.
- Reclaim unused immutable aggregate payloads only with a complete root model:
  invocation results, cross-frame writes, session/acquired publication and virtual
  descriptors. Live frames alone are insufficient.
- Prepare raw/inherited resource storage when a concrete consumer requires it.

## Validation boundaries

Measure growing 10/100/1,000-command sessions with prelude, rejections and live
bindings. Keep differential and allocation-failure coverage, failed-reserve/close
retry, forwarding and extraction cases. Pair new Safety proofs with stale alias,
independent-call, aliasing and duplicate-cleanup rejections; bound selector growth
and check recursive convergence. Review I/O/system fixture isolation by actual
shared resources, never by category alone.

Measurements: [compiler performance](../docs/compiler-performance.md).
Semantics: [Safety](../description/34_safety_model.md#precision-of-safety-effects)
and [virtual contracts](../description/134_virtual_types.md).
Execution: [usage](../docs/usage.md#experimental-bytecode-execution).
New IRs, general invalidation, semantic parallelism and incremental editor
machinery need evidence of a concrete benefit. Representation experiments belong
in [workload-driven exploration](0.6.md).
