-- Start here: four triangular faces form a closed tetrahedron.
-- Face indices wind outwards. The constructor infers Float64 and three
-- vertices per face from the arrays; the final loop shows boundary traversal.
test usage_closed_tetrahedron := (.system: System) -> !() {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    points: [4]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (0.0, 1.0, 0.0),
        (0.0, 0.0, 1.0)
    )
    faces: [4][3]UIntNative = (
        (0, 2, 1),
        (0, 1, 3),
        (1, 2, 3),
        (2, 0, 3)
    )
    model ::= t.from_equal_length_faces(.points = view(&points), .faces = view(&faces))!
    counts ::= t.entity_counts(&model)
    testing.expect(counts.vertices == 4 and counts.edges == 6 and counts.faces == 4)!
    testing.expect(t.is_closed(&model).ok)!
    -- A face references an oriented boundary loop. The borrowed range follows
    -- its half-edges once without allocating traversal storage.
    boundary_id ::= t.face_loop(&model, .face = (.value = 0))!
    visited :: UIntNative = 0
    for entry in [t.loop_halfedges(&model, .loop = boundary_id)!] {
        position ::= [
            t.point(&model, .vertex = [t.halfedge_vertex(entry.halfedge)!])!
        ]
        testing.expect(position.z == 0.0)!
        visited = visited + 1
    }
    testing.expect(visited == 3)!
}
