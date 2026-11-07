-- Merge two coplanar triangles into one square face.
-- The result owns a new model plus source-to-result correspondences.
-- Query that correspondence instead of assuming a face kept its old ID.
test usage_merge_coplanar_faces := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    points: [4]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (1.0, 1.0, 0.0),
        (0.0, 1.0, 0.0)
    )
    triangles: [2][3]UIntNative = (
        (0, 1, 2),
        (0, 2, 3)
    )
    source ::= [
        t.from_equal_length_faces(
            .points = view(&points), .faces = view(&triangles), .require_closed = false
        )!
    ]
    -- The operation returns a new model and an explicit correspondence.
    operation ::= [
        t.merge_coplanar_faces(&source, .first = (.value = 0), .second = (.value = 1))!
    ]
    testing.expect(t.entity_counts(&operation.model).faces == 1)!
    face ::= t.mapped_face(&operation, .source_face = (.value = 1))!
    [
        testing.expect([[t.face_info(&operation.model, .face = face)!].loop_count == 1])!
    ]
    testing.expect(t.entity_counts(&source).faces == 2)!
}
