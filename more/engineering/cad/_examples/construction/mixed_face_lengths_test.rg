-- A square pyramid combines a quad base with four triangular sides.
-- Flatten the vertex indices and supply one length per face, in the same order.
-- The constructor computes offsets; callers do not need to store them.
test usage_any_length_pyramid := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    points: [5]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (1.0, 1.0, 0.0),
        (0.0, 1.0, 0.0),
        (0.5, 0.5, 1.0)
    )
    vertex_indices: [16]UIntNative = (0, 3, 2, 1, 0, 1, 4, 1, 2, 4, 2, 3, 4, 3, 0, 4)
    face_lengths: [5]UIntNative = (4, 3, 3, 3, 3)
    model ::= [
        t.from_any_length_faces(
            .points         = view(&points)
            .vertex_indices = view(&vertex_indices)
            .face_lengths   = view(&face_lengths)
        )!
    ]
    counts ::= t.entity_counts(&model)
    testing.expect(counts.vertices == 5 and counts.edges == 8 and counts.faces == 5)!
    testing.expect(counts.halfedges == 16 and t.is_closed(&model).ok)!
    base ::= [
        t.loop_info(&model, .loop = [t.face_loop(&model, .face = (.value = 0))!])!
    ]
    side ::= [
        t.loop_info(&model, .loop = [t.face_loop(&model, .face = (.value = 1))!])!
    ]
    testing.expect(base.count == 4 and side.count == 3)!
}
