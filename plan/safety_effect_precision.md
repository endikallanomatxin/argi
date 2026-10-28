# Safety effect precision

Design and implementation boundaries: [Safety](../description/34_safety_model.md#precision-of-safety-effects)
and [virtual contracts](../description/134_virtual_types.md).
Prioritize a concrete core consumer before extending syntax or proofs.

- Extend joint conditional generation, consumption, relocation and cleanup beyond
  the existing single-result proof rules. Require exact caller storage identities;
  dependency permissions alone cannot establish ownership or occupancy.
- Extend conditional whole-storage transitions through stored call results,
  indirect output writes and loops rewriting discriminants. Retain intervening
  writes and cleanup; never restore an older caller snapshot when a tag is tested.
- Support conditional hidden retention/replacement, grouped opaque mappings and
  selectors through arbitrary output fields.
- Extend ownership transitions through erased receivers when their concrete
  storage and cleanup identities can be represented. Keep Resizable static until
  its hidden transitions are expressible.

Retain failed-reserve/close retry, wrapper forwarding and extraction cases. Pair
new proofs with stale-generation, independent-call, aliasing and duplicate-cleanup
rejections; measure representation size and recursive convergence. Do not revive
old caller snapshots or expand independent selector combinations without bounds.
