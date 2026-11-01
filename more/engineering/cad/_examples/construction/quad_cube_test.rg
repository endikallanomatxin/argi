-- The same constructor accepts four vertices per face and Float32 coordinates.
-- Six quads describe a cube; its bottom face has an outward normal along -Z.
test usage_float32_cube_with_quad_faces := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    points: [8]g.Point#(Float32) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (1.0, 1.0, 0.0),
        (0.0, 1.0, 0.0),
        (0.0, 0.0, 1.0),
        (1.0, 0.0, 1.0),
        (1.0, 1.0, 1.0),
        (0.0, 1.0, 1.0)
    )
    faces: [6][4]UIntNative = (
        (0, 3, 2, 1),
        (4, 5, 6, 7),
        (0, 1, 5, 4),
        (1, 2, 6, 5),
        (2, 3, 7, 6),
        (3, 0, 4, 7)
    )
    model ::= t.from_equal_length_faces(.points = view(&points), .faces = view(&faces))!
    counts ::= t.entity_counts(&model)
    testing.expect(counts.vertices == 8 and counts.edges == 12 and counts.faces == 6)!
    boundary ::= [
        t.loop_info(&model, .loop = [t.face_loop(&model, .face = (.value = 0))!])!
    ]
    testing.expect(boundary.count == 4)!
    plane ::= t.face_plane(&model, .face = (.value = 0))!
    testing.expect(plane.normal.z == -1.0)!
}
