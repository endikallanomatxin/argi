-- Split a square between the midpoints of opposite boundary edges.
-- An endpoint consists of a halfedge and a parameter in its traversal direction.
-- The result identifies both new faces and the newly inserted cut vertices.
test usage_split_planar_face := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    points: [4]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (2.0, 0.0, 0.0),
        (2.0, 2.0, 0.0),
        (0.0, 2.0, 0.0)
    )
    faces: [1][4]UIntNative = ((0, 1, 2, 3))
    source ::= [
        t.from_equal_length_faces(
            .points = view(&points), .faces = view(&faces), .require_closed = false
        )!
    ]
    boundary ::= [
        t.loop_info(&source, .loop = [t.face_loop(&source, .face = (.value = 0))!])!
    ]
    -- Find opposite edges by following connectivity, not by adding to IDs.
    first ::= boundary.first
    second ::= [t.halfedge_info(&source, .halfedge = first)!].next
    opposite_side ::= [t.halfedge_info(&source, .halfedge = second)!].next
    operation ::= [
        t.split_planar_face(
            &source
            .face  = (.value = 0)
            .start = (.halfedge = first, .parameter = 0.5)
            .end   = (.halfedge = opposite_side, .parameter = 0.5)
        )!
    ]
    counts ::= t.entity_counts(&operation.model)
    testing.expect(counts.faces == 2 and counts.vertices == 6 and counts.edges == 7)!
    -- A source face can map to two result faces after a split.
    images ::= t.split_face_images(&operation, .source_face = (.value = 0))!
    testing.expect(images.first == operation.faces[0])!
    match images.second {
        ..none { [testing.fail()!] }
        ..some face { [testing.expect(face.value == operation.faces[1])!] }
    }
    [
        testing.expect([[t.point(&operation.model, .vertex = operation.cut_start)!].x == 1.0])!
    ]
}
