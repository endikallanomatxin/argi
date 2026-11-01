test sketch_profile_rounded_plate_with_holes_reaches_brep := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    builder ::= SketchBuilder#(.Scalar: Float64)()!
    exterior ::= [builder | rounded_rectangle($&_, .width = 8.0, .height = 6.0, .radius = 0.5)!]
    positions: [2]g.ContourPoint#(Float64) = (
        (-2.0, 0.0),
        (2.0, 0.0)
    )
    for position in positions {
        builder | circle($&_, .center = position, .diameter = 0.5)!
    }
    drawing ::= builder | finish_sketch(~_)!
    selected ::= drawing | profile(&_, .exterior = exterior)!
    model ::= m.profile_brep(&selected)!
    counts ::= t.entity_counts(&model)
    [
        testing.expect(
            [
                counts.faces == 1
                and counts.loops == 3
                and counts.edges == 10
                and counts.vertices == 8
            ]
        )!
    ]
    testing.expect(t.is_closed(&model).ok == false)!
    -- XY sketch coordinates map to the plane's generated UV chart: u=-y,v=x.
    [
        testing.expect(
            [t.face_contains_parameters(&model, .face = (.value = 0), .u = -1.0, .v = 0.0)!]
        )!
    ]
    [
        testing.expect(
            [
                [t.face_contains_parameters(&model, .face = (.value = 0), .u = 0.0, .v = -2.0)!]
                == false
            ]
        )!
    ]
    [
        testing.expect(
            [
                [t.face_contains_parameters(&model, .face = (.value = 0), .u = 0.0, .v = 2.0)!]
                == false
            ]
        )!
    ]
    [
        testing.expect(
            [
                [t.face_contains_parameters(&model, .face = (.value = 0), .u = -3.1, .v = 0.0)!]
                == false
            ]
        )!
    ]
    for boundary in [t.face_loops(&model, .face = (.value = 0))!] {
        for entry in [t.loop_halfedges(&model, .loop = boundary.id)!] {
            parameter :: Float64 = 0.0
            while parameter <= 1.0 {
                a ::= t.halfedge_point(&model, .halfedge = entry.id, .parameter = parameter)!
                uv ::= [
                    t.halfedge_parameters(&model, .halfedge = entry.id, .parameter = parameter)!
                ]
                b ::= [
                    g.surface_point(
                        .surface = [t.face_surface(&model, .face = (.value = 0))!]
                        .u       = uv.u
                        .v       = uv.v
                    )!
                ]
                testing.expect(g.norm(g.between(.from = a, .to = b).result).value < 0.000001)!
                parameter = parameter + 0.25
            }
        }
    }
    second_profile ::= drawing | profile(&_, .exterior = exterior)!
    second ::= m.profile_brep(&second_profile)!
    testing.expect(t.entity_counts(&second).edges == counts.edges)!
}

test sketch_profile_float32_plane_and_nested_selection_errors := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    builder ::= SketchBuilder#(.Scalar: Float32)(.plane = ..xz)!
    builder | circle($&_, .diameter = 0.5)!
    exterior ::= builder | rectangle($&_, .width = 4.0, .height = 3.0)!
    drawing ::= builder | finish_sketch(~_)!
    selected ::= drawing | profile(&_, .exterior = exterior)!
    model ::= m.profile_brep(&selected)!
    normal ::= t.face_normal(&model, .face = (.value = 0), .u = 0.0, .v = 0.0)!
    testing.expect(normal.y == -1.0 and normal.x == 0.0 and normal.z == 0.0)!
    testing.expect(t.entity_counts(&model).loops == 2)!
    other ::= SketchBuilder#(.Scalar: Float32)()!
    foreign ::= other | rectangle($&_, .width = 1.0, .height = 1.0)!
    [
        testing.expect_error(
            .actual_result   = profile(&drawing, .exterior = foreign)
            .expected_reason = ..wrong_domain
        )!
    ]
}

test sketch_profile_rejects_outside_hole_without_consuming_drawing := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    builder ::= SketchBuilder#(.Scalar: Float64)()!
    exterior ::= builder | rectangle($&_, .width = 4.0, .height = 3.0)!
    builder | circle($&_, .center = (3.0, 0.0), .diameter = 0.5)!
    drawing ::= builder | finish_sketch(~_)!
    [
        testing.expect_error(
            .actual_result   = profile(&drawing, .exterior = exterior)
            .expected_reason = ..invalid_region_nesting
        )!
    ]
    testing.expect(contour_count(&drawing).count == 2)!
    spans ::= contour_spans(&drawing, .contour = exterior)!
    testing.expect(Indexable#(ArrayView#(g.ContourSpan#(Float64))).length(&spans).count == 4)!
}

_arc_profile := #(.Scalar: Type: Float) (
    .quarters : Bool = false, .rotate: Bool = false, .allocator: $&Virtual#(Allocator)
) -> (.result: Errable#(t.Model#(Scalar), t.BrepErrors)) {
    builder ::= SketchBuilder#(.Scalar: Scalar)(.tolerance = 0.00001, .allocator = allocator)!
    points: [4]g.ContourPoint#(Scalar) = (
        (2.0, 0.0),
        (0.0, 2.0),
        (-2.0, 0.0),
        (0.0, -2.0)
    )
    spans: [4]g.ContourSpan#(Scalar) = (
        (.start = points[0], .end = points[2], .sweep = 3.141592653589793),
        (.start = points[2], .end = points[0], .sweep = 3.141592653589793),
        (.start = points[0], .end = points[1]),
        (.start = points[1], .end = points[0])
    )
    count :: UIntNative = 2
    if quarters {
        count = 4
        i :: UIntNative = 0
        while i < count {
            spans[i] = (
                .start = points[i]
                .end   = points[[i + 1] % 4]
                .sweep = 1.5707963267948966
            )
            i = i + 1
        }
    }
    if rotate {
        first ::= spans[0]
        i :: UIntNative = 1
        while i < count {
            spans[i - 1] = spans[i]
            i = i + 1
        }
        spans[count - 1] = first
    }
    span_view ::= view(&spans)
    boundary ::= slice(&span_view, .start = 0, .count = count)!
    exterior ::= builder | contour($&_, .spans = boundary, .allocator = allocator)!
    builder | circle($&_, .diameter = 1.0, .allocator = allocator)!
    drawing ::= builder | finish_sketch(~_)!
    selected ::= profile(&drawing, .exterior = exterior, .allocator = allocator)!
    result = m.profile_brep(&selected, .allocator = allocator)
}

test sketch_arc_only_profile_subdivision_rotation_and_inversion := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    halves ::= _arc_profile#(.Scalar: Float64)()!
    quarters ::= _arc_profile#(.Scalar: Float64)(.quarters = true, .rotate = true)!
    inverse ::= t.reverse_orientation(&halves)!
    testing.expect(t.entity_counts(&halves).edges == 3)!
    testing.expect(t.entity_counts(&quarters).edges == 5)!
    u :: Float64 = -2.5
    while u <= 2.5 {
        v :: Float64 = -2.5
        while v <= 2.5 {
            inside ::= [
                t.face_contains_parameters(&halves, .face = (.value = 0), .u = u, .v = v)!
            ]
            [
                testing.expect(
                    [
                        inside
                        == [
                            t.face_contains_parameters(
                                &quarters, .face = (.value = 0), .u = u, .v = v
                            )!
                        ]
                    ]
                )!
            ]
            [
                testing.expect(
                    [
                        inside
                        == [
                            t.face_contains_parameters(
                                &inverse, .face = (.value = 0), .u = u, .v = v
                            )!
                        ]
                    ]
                )!
            ]
            radius ::= hypot(.left = u, .right = v).result
            testing.expect(inside == [radius >= 0.5 and radius <= 2.0])!
            v = v + 0.25
        }
        u = u + 0.25
    }
    model32 ::= _arc_profile#(.Scalar: Float32)()!
    [
        testing.expect(
            [t.face_contains_parameters(&model32, .face = (.value = 0), .u = 0.0, .v = 1.0)!]
        )!
    ]
}

test sketch_circular_profile_preserves_boundary_tolerance := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    builder ::= SketchBuilder#(.Scalar: Float64)()!
    exterior ::= builder | circle($&_, .diameter = 2.0)!
    drawing ::= builder | finish_sketch(~_)!
    selected ::= drawing | profile(&_, .exterior = exterior)!
    model ::= m.profile_brep(&selected)!
    spans ::= contour_spans(&drawing, .contour = exterior)!
    radii: [5]Float64 = (0.5, 0.9999995, 1.0, 1.0000005, 1.000002)
    for radius in radii {
        expected ::= true
        match [g.locate_in_contour_spans(.spans = spans, .point = (radius, 0.0))!] {
            ..inside {}
            ..boundary {}
            ..outside { expected = false }
        }
        [
            testing.expect(
                [
                    expected
                    == [
                        t.face_contains_parameters(
                            &model, .face = (.value = 0), .u = 0.0, .v = radius
                        )!
                    ]
                ]
            )!
        ]
    }
}

test sketch_arc_only_profile_with_distinct_circle_centers := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    builder ::= SketchBuilder#(.Scalar: Float64)()!
    square: Float64 = 3.0
    height ::= sqrt(square).result
    spans: [2]g.ContourSpan#(Float64) = (
        (
            .start  = (0.0, 0.0 - height)
            .end    = (0.0, height)
            .center = (-1.0, 0.0)
            .sweep  = 2.0943951023931953
        ),
        (
            .start  = (0.0, height)
            .end    = (0.0, 0.0 - height)
            .center = (1.0, 0.0)
            .sweep  = 2.0943951023931953
        )
    )
    exterior ::= builder | contour($&_, .spans = view(&spans))!
    builder | circle($&_, .diameter = 0.5)!
    drawing ::= builder | finish_sketch(~_)!
    selected ::= drawing | profile(&_, .exterior = exterior)!
    model ::= m.profile_brep(&selected)!
    [
        testing.expect(
            [t.face_contains_parameters(&model, .face = (.value = 0), .u = 0.0, .v = 0.5)!]
        )!
    ]
    [
        testing.expect(
            [
                [t.face_contains_parameters(&model, .face = (.value = 0), .u = 0.0, .v = 0.0)!]
                == false
            ]
        )!
    ]
    [
        testing.expect(
            [
                [t.face_contains_parameters(&model, .face = (.value = 0), .u = 0.0, .v = 1.1)!]
                == false
            ]
        )!
    ]
    [
        testing.expect(
            [t.face_contains_parameters(&model, .face = (.value = 0), .u = 1.5, .v = 0.0)!]
        )!
    ]
}
