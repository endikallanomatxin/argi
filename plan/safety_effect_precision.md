# Safety effect precision

Design and implementation boundaries: [Safety](../description/34_safety_model.md#precision-of-safety-effects)
and [virtual contracts](../description/134_virtual_types.md).
Prioritize a concrete core consumer before extending syntax or proofs.

- Extend joint conditional generation, consumption, relocation and cleanup beyond
  the existing single-result proof rules. Require exact caller storage identities;
  dependency permissions alone cannot establish ownership or occupancy.
- Preserve correlations through branch-assigned/rewritten outputs, intermediate
  effects and nontrivial cleanup where every selected exit proves them. Concrete
  consumer: retain a `PriorityQueue.peek_reference` borrow in the error branch of
  a refused `push`, then retry growth (extend `collections/149_owned_ordering`).
  The current analysis applies `ensure_capacity` may-effects before splitting
  propagation exits. Refine effects at the original call; never restore a caller
  snapshot across later writes or cleanup.
- Support conditional hidden retention/replacement, grouped opaque mappings and
  selectors through arbitrary output fields.
- Extend ownership transitions through erased receivers when their concrete
  storage and cleanup identities can be represented. Keep Resizable static until
  its hidden transitions are expressible.

Retain failed-reserve/close retry, wrapper forwarding and extraction cases. Pair
new proofs with stale-generation, independent-call, aliasing and duplicate-cleanup
rejections; measure representation size and recursive convergence. Do not revive
old caller snapshots or expand independent selector combinations without bounds.
