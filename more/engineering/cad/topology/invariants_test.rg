test model_invariant_under_face_order_vertex_numbering_and_winding := (.system: System) -> !() {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    original: [4]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (0.0, 1.0, 0.0),
        (0.0, 0.0, 1.0)
    )
    base: [4][3]UIntNative = (
        (0, 2, 1),
        (0, 1, 3),
        (1, 2, 3),
        (2, 0, 3)
    )
    variant :: UIntNative = 0
    while variant < 8 {
        points :: [4]g.Point#(Float64) = original
        faces :: [4][3]UIntNative = base
        face :: UIntNative = 0
        while face < 4 {
            source_face ::= face
            if variant % 2 == 1 { source_face = 3 - face }
            corner :: UIntNative = 0
            while corner < 3 {
                source_corner ::= [corner + 1] % 3
                if variant / 4 == 1 { source_corner = 2 - source_corner }
                vertex ::= base[source_face][source_corner]
                if [variant / 2] % 2 == 1 { vertex = 3 - vertex }
                faces[face][corner] = vertex
                corner = corner + 1
            }
            if [variant / 2] % 2 == 1 { points[face] = original[3 - face] }
            face = face + 1
        }
        model ::= from_equal_length_faces(.points = view(&points), .faces = view(&faces))!
        counts ::= entity_counts(&model)
        testing.expect(counts.vertices == 4 and counts.edges == 6 and counts.faces == 4)!
        testing.expect(counts.halfedges == 12 and is_closed(&model).ok)!
        face = 0
        while face < 4 {
            face_id ::= face | convert#(.to: FaceId)(_)
            plane ::= face_plane(&model, .face = face_id)!
            interior: g.Point#(Float64) = (0.25, 0.25, 0.25)
            offset ::= g.between(.from = plane.origin, .to = interior).result
            side ::= g.dot(.left = plane.normal, .right = offset).value
            if variant / 4 == 0 {
                testing.expect(side < 0.0)!
            } else {
                testing.expect(side > 0.0)!
            }
            for entry in [
                loop_halfedges(&model, .loop = [face_loop(&model, .face = face_id)!])!
            ] {
                match [opposite(&model, .halfedge = entry.id)!] {
                    ..none {
                        testing.fail()!
                    }
                    ..some paired {
                        other ::= halfedge_info(&model, .halfedge = paired.value)!
                        endpoint ::= halfedge_info(&model, .halfedge = entry.halfedge.next)!
                        [
                            testing.expect(
                                [[halfedge_vertex(other)!] == [halfedge_vertex(endpoint)!]]
                            )!
                        ]
                    }
                }
            }
            face = face + 1
        }
        variant = variant + 1
    }
}
