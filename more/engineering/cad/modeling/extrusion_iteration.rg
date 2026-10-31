-- A borrowed, repeatable range of generated wall IDs in directed profile-span
-- order. Traversal does not allocate and never assumes consecutive face IDs.
ExtrusionWalls := (._faces: ArrayView#(t.FaceId))

ExtrusionWallIterator := (._faces: ArrayView#(t.FaceId), ._index: UIntNative)

extrusion_contour_walls := #(.Scalar: Type: Float) (
    .extrusion: &ExtrusionResult#(Scalar), .contour: UIntNative
) -> (.result: Errable#(ExtrusionWalls, (..out_of_bounds))) {
    count ::= length(&extrusion&._contour_offsets).count
    if contour >= count - 1 {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    first ::= get(&extrusion&._contour_offsets, .index = contour)!
    end ::= get(&extrusion&._contour_offsets, .index = contour + 1)!
    faces ::= view(&extrusion&._walls)
    selected ::= slice(&faces, .start = first, .count = end - first)!
    result = ..ok(._faces = selected)
}

implement Iterable#(ExtrusionWalls) (
    .Item         : Type = t.FaceId
    .IteratorType : Type = ExtrusionWallIterator

    .to_iterator = (.value: &ExtrusionWalls) -> (.iterator: ExtrusionWallIterator) {
        iterator = (._faces = value&._faces, ._index = 0)
    }
)

implement Iterator#(ExtrusionWallIterator) (
    .Item : Type = t.FaceId

    .has_next = (.self: &ExtrusionWallIterator) -> (.ok: Bool) {
        ok = self&._index < length(&self&._faces).count
    }

    .next = (.self: $&ExtrusionWallIterator) -> (.value: t.FaceId) {
        -- Like core iterators, next requires has_next; exhaustion aborts.
        value = unwrap_or_abort(.value = get(&self&._faces, .index = self&._index)).result
        self&._index = self&._index + 1
    }
)
