# Safety contract follow-ups

Prioritize a concrete core consumer before extending syntax.
Design boundary: [effect precision](safety_effect_precision.md).

- Correlate joint guards with generation, opaque-state, ownership, and cleanup
  effects. Joint conditional consumption/relocation needs representable identities.
- Preserve call provenance through branch-assigned outputs, intermediate calls,
  computed choice tests, and error propagation.
- Add source selectors for record fields without expanding unrelated variants.
- Model initialization and conditional hidden retention/replacement post-values.
- Extend storage identities to grouped domains, reference mappings, erased
  receivers, and indexed owners before permitting their ownership transitions.
- Prove exact hidden ownership transfer and returned domain identity; dependency
  permissions alone must not establish occupancy or ownership.
- Extend exact identity/transfer proofs beyond straight-line lexical forwarding.
- Validate aggregate/result facts after invalidation without discarding ownership.

Pair positive cases with stale-root, aliasing, duplicate-cleanup, and undeclared
retention rejections. Keep Resizable static until hidden transitions are expressible.
