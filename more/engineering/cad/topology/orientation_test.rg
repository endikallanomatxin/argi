test model_orientation_preserves_spherical_region := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    original ::= _brep_hemisphere#(.Scalar: Float64)(.allocator = allocator)!
    inverted ::= reverse_orientation(&original)!
    restored ::= reverse_orientation(&inverted)!
    testing.expect(is_closed(&inverted).ok and entity_counts(&inverted).edges == 1)!
    testing.expect([face_info(&inverted, .face = (.value = 0))!].reversed)!
    [
        testing.expect([[face_info(&inverted, .face = (.value = 1))!].reversed == false])!
    ]
    [
        testing.expect(
            [face_contains_parameters(&inverted, .face = (.value = 0), .u = 9.0, .v = 1.0)!]
        )!
    ]
    [
        testing.expect(
            [
                [face_contains_parameters(&inverted, .face = (.value = 0), .u = 9.0, .v = -1.0)!]
                == false
            ]
        )!
    ]
    [
        testing.expect(
            [face_contains_parameters(&inverted, .face = (.value = 1), .u = 0.0, .v = 0.0)!]
        )!
    ]
    t :: Float64 = 0.0
    while t <= 1.0 {
        a ::= halfedge_point(&original, .halfedge = (.value = 0), .parameter = t)!
        b ::= halfedge_point(&inverted, .halfedge = (.value = 0), .parameter = 1.0 - t)!
        c ::= halfedge_point(&restored, .halfedge = (.value = 0), .parameter = t)!
        [_trim_near_point(.a = a, .b = b, .tolerance = 0.000001)!]
        [_trim_near_point(.a = a, .b = c, .tolerance = 0.000001)!]
        uv ::= halfedge_parameters(&inverted, .halfedge = (.value = 0), .parameter = 1.0 - t)!
        point ::= [
            g.surface_point(
                .surface = [face_surface(&inverted, .face = (.value = 0))!]
                .u       = uv.u
                .v       = uv.v
            )!
        ]
        [_trim_near_point(.a = a, .b = point, .tolerance = 0.000001)!]
        t = t + 0.125
    }
    [
        testing.expect([[face_info(&restored, .face = (.value = 0))!].reversed == false])!
    ]
    testing.expect([face_info(&restored, .face = (.value = 1))!].reversed)!
    [_validate_vertices(&inverted._topology, .allocator = allocator)!]
}

test model_orientation_preserves_vertex_incidence_and_ids := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
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
    original ::= from_equal_length_faces(.points = view(&points), .faces = view(&faces))!
    inverted ::= reverse_orientation(&original)!
    restored ::= reverse_orientation(&inverted)!
    [_validate_vertices(&inverted._topology, .allocator = allocator)!]
    testing.expect(is_closed(&inverted).ok)!
    i :: UIntNative = 0
    while i < entity_counts(&original).halfedges {
        id ::= i | convert#(.to: HalfEdgeId)(_)
        a ::= halfedge_info(&original, .halfedge = id)!
        b ::= halfedge_info(&inverted, .halfedge = id)!
        c ::= halfedge_info(&restored, .halfedge = id)!
        successor ::= halfedge_info(&original, .halfedge = a.next)!
        [
            testing.expect([[halfedge_vertex(b)!] == [halfedge_vertex(successor)!]])!
        ]
        [
            testing.expect([[halfedge_info(&inverted, .halfedge = a.next)!].next == id])!
        ]
        testing.expect(a.edge == b.edge and a.loop == b.loop and a.reversed != b.reversed)!
        testing.expect(a.next == c.next and a.reversed == c.reversed)!
        [
            testing.expect([[halfedge_vertex(a)!] == [halfedge_vertex(c)!]])!
        ]
        i = i + 1
    }
}

test model_orientation_float32_periodic_faces := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    frame ::= [
        g.frame#(Float32)(.origin = (0.0, 0.0, 0.0), .axis = (0.0, 0.0, 1.0))!
    ]
    sphere: g.Surface#(Float32) = ..sphere(.frame = frame, .radius = 2.0)
    original ::= from_periodic_surface(.surface = sphere)!
    inverted ::= reverse_orientation(&original)!
    testing.expect(entity_counts(&inverted).loops == 0 and is_closed(&inverted).ok)!
    testing.expect([face_info(&inverted, .face = (.value = 0))!].reversed)!
    cylinder: g.Surface#(Float32) = ..cylinder(.frame = frame, .radius = 2.0)
    open ::= from_periodic_surface(.surface = cylinder)!
    reversed ::= reverse_orientation(&open)!
    testing.expect(is_closed(&reversed).ok == false)!
    testing.expect(entity_counts(&reversed).edges == 2)!
    [_validate_vertices(&reversed._topology, .allocator = allocator)!]
}

test model_orientation_open_boundary_fans := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    input ::= _triangle()
    original ::= [
        from_any_length_faces(
            .points         = view(&input.points)
            .vertex_indices = view(&input.indices)
            .face_lengths   = view(&input.face_lengths)
            .require_closed = false
        )!
    ]
    inverted ::= reverse_orientation(&original)!
    [_validate_vertices(&inverted._topology, .allocator = allocator)!]
    testing.expect(is_closed(&inverted).ok == false)!
    testing.expect(entity_counts(&inverted).vertices == 3)!
}

test model_orientation_hole_walk_and_bridge := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    input ::= _planar_annulus()
    original ::= [
        from_planar_faces(
            .points           = view(&input.points)
            .vertex_indices   = view(&input.indices)
            .contour_lengths  = view(&input.lengths)
            .face_loop_counts = view(&input.face_loops)
            .require_closed   = false
        )!
    ]
    inverted ::= reverse_orientation(&original)!
    [_validate_vertices(&inverted._topology, .allocator = allocator)!]
    [
        testing.expect([[face_info(&inverted, .face = (.value = 0))!].loop_count == 2])!
    ]
    [
        testing.expect(
            [
                [face_plane(&inverted, .face = (.value = 0))!].normal.z
                == [face_plane(&original, .face = (.value = 0))!].normal.z
            ]
        )!
    ]
    bridge ::= [
        bridge_planar_face(
            &original
            .face     = (.value = 0)
            .exterior = (.halfedge = (.value = 0), .parameter = 0.0)
            .hole     = (.halfedge = (.value = 4), .parameter = 0.0)
        )!
    ]
    reversed_bridge ::= reverse_orientation(&bridge.model)!
    [_validate_vertices(&reversed_bridge._topology, .allocator = allocator)!]
    uses :: UIntNative = 0
    for entry in [loop_halfedges(&reversed_bridge, .loop = (.value = 0))!] {
        if entry.halfedge.edge == bridge.bridge_edge { uses = uses + 1 }
    }
    testing.expect(uses == 2 and entity_counts(&reversed_bridge).loops == 1)!
}
