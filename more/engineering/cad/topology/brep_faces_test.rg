_arc_annulus := #(.Scalar: Type: Float) (
    .allocator   : Virtual#(Allocator),
    .hole_offset : Scalar      = 0.0,
    .hole_radius : Scalar      = 1.0,
    .phase       : Scalar      = 0.0,
    .partition   : Scalar      = 0.5,
    .inverted    : Bool        = false,
    .close       : Bool        = false
) -> (.result: Errable#(Model#(Scalar), BrepErrors)) {
    builder ::= BrepBuilder#(Scalar)(.allocator = allocator)!
    basis ::= g.frame#(Scalar)(.origin = (0.0, 0.0, 0.0), .axis = (0.0, 0.0, 1.0))!
    plane: g.Surface#(Scalar) = ..plane(
        .value = (.origin = basis.origin, .normal = basis.z)
    )
    surface ::= builder | declare_surface($&_, .surface = plane, .allocator = allocator)!
    outer: g.Circle#(Scalar) = (.frame = basis, .radius = 3.0)
    inner_frame: g.Frame#(Scalar) = (
        .origin = (
            .x = basis.x.x * hole_offset
            .y = basis.x.y * hole_offset
            .z = [basis.x.z * hole_offset]
        )
        .x = basis.x
        .y = basis.y
        .z = basis.z
    )
    inner: g.Circle#(Scalar) = (.frame = inner_frame, .radius = hole_radius)
    outer_curve: Curve#(Scalar) = ..circle(.value = outer)
    inner_curve: Curve#(Scalar) = ..circle(.value = inner)
    outer_id ::= builder | declare_curve($&_, .curve = outer_curve, .allocator = allocator)!
    inner_id ::= builder | declare_curve($&_, .curve = inner_curve, .allocator = allocator)!
    tau: Scalar = 6.283185307179586
    begin_angle ::= phase * tau
    middle_angle ::= [phase + partition] * tau
    end_angle ::= [phase + 1.0] * tau
    a ::= declare_vertex(
        $&builder
        .point     = g.circle_point(.circle = outer, .angle = begin_angle)!
        .allocator = allocator
    )!
    b ::= declare_vertex(
        $&builder
        .point     = g.circle_point(.circle = outer, .angle = middle_angle)!
        .allocator = allocator
    )!
    c ::= declare_vertex(
        $&builder
        .point     = g.circle_point(.circle = inner, .angle = begin_angle)!
        .allocator = allocator
    )!
    d ::= declare_vertex(
        $&builder
        .point     = g.circle_point(.circle = inner, .angle = middle_angle)!
        .allocator = allocator
    )!
    first: CurveInterval#(Scalar) = (.start = phase, .end = [phase + partition])
    second: CurveInterval#(Scalar) = (.start = [phase + partition], .end = [phase + 1.0])
    ab ::= declare_edge(
        $&builder
        .curve     = outer_id
        .interval  = first
        .start     = a
        .end       = b
        .allocator = allocator
    )!
    ba ::= declare_edge(
        $&builder
        .curve     = outer_id
        .interval  = second
        .start     = b
        .end       = a
        .allocator = allocator
    )!
    cd ::= declare_edge(
        $&builder
        .curve     = inner_id
        .interval  = first
        .start     = c
        .end       = d
        .allocator = allocator
    )!
    dc ::= declare_edge(
        $&builder
        .curve     = inner_id
        .interval  = second
        .start     = d
        .end       = c
        .allocator = allocator
    )!
    outer_first: PCurve#(Scalar) = ..ellipse(
        .center = (.u = 0.0, .v = 0.0)
        .cosine = (.u = 3.0, .v = 0.0)
        .sine   = (.u = 0.0, .v = 3.0)
        .start  = begin_angle
        .end    = middle_angle
    )
    outer_second: PCurve#(Scalar) = ..ellipse(
        .center = (.u = 0.0, .v = 0.0)
        .cosine = (.u = 3.0, .v = 0.0)
        .sine   = (.u = 0.0, .v = 3.0)
        .start  = middle_angle
        .end    = end_angle
    )
    inner_first: PCurve#(Scalar) = ..ellipse(
        .center = (.u = hole_offset, .v = 0.0)
        .cosine = (.u = hole_radius, .v = 0.0)
        .sine   = (.u = 0.0, .v = hole_radius)
        .start  = begin_angle
        .end    = middle_angle
    )
    inner_second: PCurve#(Scalar) = ..ellipse(
        .center = (.u = hole_offset, .v = 0.0)
        .cosine = (.u = hole_radius, .v = 0.0)
        .sine   = (.u = 0.0, .v = hole_radius)
        .start  = middle_angle
        .end    = end_angle
    )
    boundaries :: [4]TrimUse#(Scalar) = (
        (.edge = ab, .pcurve = outer_first),
        (.edge = ba, .pcurve = outer_second),
        (.edge = dc, .pcurve = inner_second, .reversed = true),
        (.edge = cd, .pcurve = inner_first, .reversed = true)
    )
    if inverted {
        boundaries = (
            (.edge = ba, .pcurve = outer_second, .reversed = true),
            (.edge = ab, .pcurve = outer_first, .reversed = true),
            (.edge = cd, .pcurve = inner_first),
            (.edge = dc, .pcurve = inner_second)
        )
    }
    lengths: [2]UIntNative = (2, 2)
    declare_trimmed_face(
        $&builder
        .surface         = surface
        .boundaries      = view(&boundaries)
        .contour_lengths = view(&lengths)
        .reversed        = inverted
        .allocator       = allocator
    )!
    if close {
        opposite :: [4]TrimUse#(Scalar) = (
            boundaries[1],
            boundaries[0],
            boundaries[3],
            boundaries[2]
        )
        i :: UIntNative = 0
        while i < 4 {
            opposite[i].reversed = [opposite[i].reversed == false]
            i = i + 1
        }
        declare_trimmed_face(
            $&builder
            .surface         = surface
            .boundaries      = view(&opposite)
            .contour_lengths = view(&lengths)
            .reversed        = [inverted == false]
            .allocator       = allocator
        )!
    }
    model ::= builder | finish_brep(~_, .require_closed = close, .allocator = allocator)!
    result = ..ok ~model
}

test model_arc_annulus_float64 := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    model ::= _arc_annulus#(.Scalar: Float64)(.allocator = allocator)!
    counts ::= entity_counts(&model)
    [
        testing.expect(
            [
                counts.vertices == 4
                and counts.edges == 4
                and counts.loops == 2
                and counts.faces == 1
            ]
        )!
    ]
    storage ::= geometry_storage_info(&model)
    testing.expect(storage.curves == 2 and storage.intervals == 4 and storage.pcurves == 4)!
    [
        testing.expect(
            [face_contains_parameters(&model, .face = (.value = 0), .u = 2.0, .v = 0.0)!]
        )!
    ]
    [
        testing.expect(
            [
                [face_contains_parameters(&model, .face = (.value = 0), .u = 0.0, .v = 0.0)!]
                == false
            ]
        )!
    ]
    [
        testing.expect(
            [
                [face_contains_parameters(&model, .face = (.value = 0), .u = 4.0, .v = 0.0)!]
                == false
            ]
        )!
    ]
    [
        testing.expect(
            [face_contains_parameters(&model, .face = (.value = 0), .u = 1.0, .v = 0.0)!]
        )!
    ]
    for loop in [face_loops(&model, .face = (.value = 0))!] {
        for use in [loop_halfedges(&model, .loop = loop.id)!] {
            t :: Float64 = 0.0
            while t <= 1.0 {
                point ::= halfedge_point(&model, .halfedge = use.id, .parameter = t)!
                uv ::= halfedge_parameters(&model, .halfedge = use.id, .parameter = t)!
                expected ::= [
                    g.surface_point(
                        .surface = [face_surface(&model, .face = (.value = 0))!]
                        .u       = uv.u
                        .v       = uv.v
                    )!
                ]
                [_trim_near_point(.a = point, .b = expected, .tolerance = 0.000001)!]
                t = t + 0.125
            }
            end ::= halfedge_point(&model, .halfedge = use.id, .parameter = 1.0)!
            next ::= halfedge_info(&model, .halfedge = use.halfedge.next)!
            [
                _trim_near_point(
                    .a = end
                    .b = [
                        point(&model, .vertex = [halfedge_vertex(next)!])!
                    ]
                    .tolerance = 0.000001
                )!
            ]
        }
    }
}

test model_arc_annulus_float32_inversion := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    model ::= _arc_annulus#(.Scalar: Float32)(.allocator = allocator)!
    reversed ::= reverse_orientation(&model)!
    constructed ::= _arc_annulus#(.Scalar: Float32)(.allocator = allocator, .inverted = true)!
    [
        testing.expect(
            [face_contains_parameters(&reversed, .face = (.value = 0), .u = 2.0, .v = 0.0)!]
        )!
    ]
    [
        testing.expect(
            [
                [face_contains_parameters(&reversed, .face = (.value = 0), .u = 0.0, .v = 0.0)!]
                == false
            ]
        )!
    ]
    [
        testing.expect(
            [face_contains_parameters(&constructed, .face = (.value = 0), .u = 2.0, .v = 0.0)!]
        )!
    ]
    [
        testing.expect(
            [
                [
                    face_contains_parameters(
                        &constructed, .face = (.value = 0), .u = 0.0, .v = 0.0
                    )!
                ]
                == false
            ]
        )!
    ]
    [_validate_vertices(&reversed._topology, .allocator = allocator)!]
}

test model_arc_annulus_offset_and_rejected_nesting := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    model ::= [
        _arc_annulus#(.Scalar: Float64)(
            .allocator = allocator, .hole_offset = 1.0, .hole_radius = 0.5
        )!
    ]
    [
        testing.expect(
            [
                [face_contains_parameters(&model, .face = (.value = 0), .u = 1.0, .v = 0.0)!]
                == false
            ]
        )!
    ]
    [
        testing.expect(
            [face_contains_parameters(&model, .face = (.value = 0), .u = 0.0, .v = 0.0)!]
        )!
    ]
    [
        testing.expect_error(
            .actual_result = _arc_annulus#(.Scalar: Float64)(
                .allocator = allocator, .hole_offset = 5.0
            )
            .expected_reason = ..invalid_region_nesting
        )!
    ]
    [
        testing.expect_error(
            .actual_result = _arc_annulus#(.Scalar: Float64)(
                .allocator = allocator, .hole_offset = 4.0
            )
            .expected_reason = ..intersecting_contours
        )!
    ]
    [
        testing.expect_error(
            .actual_result = _arc_annulus#(.Scalar: Float64)(
                .allocator = allocator, .hole_offset = 2.0
            )
            .expected_reason = ..intersecting_contours
        )!
    ]
}

test model_arc_rejections_preserve_builder_and_rotated_loop := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    builder ::= BrepBuilder#(Float64)()!
    basis ::= [
        g.frame#(Float64)(.origin = (0.0, 0.0, 0.0), .axis = (0.0, 0.0, 1.0))!
    ]
    circle: g.Circle#(Float64) = (.frame = basis, .radius = 2.0)
    curve_value: Curve#(Float64) = ..circle(.value = circle)
    curve ::= builder | declare_curve($&_, .curve = curve_value)!
    a ::= [
        declare_vertex($&builder, .point = [g.circle_point(.circle = circle, .angle = 0.0)!])!
    ]
    b ::= [
        declare_vertex(
            $&builder, .point = [g.circle_point(.circle = circle, .angle = 3.141592653589793)!]
        )!
    ]
    first: CurveInterval#(Float64) = (.start = 0.0, .end = 0.5)
    last: CurveInterval#(Float64) = (.start = 0.5, .end = 1.0)
    invalid_interval: CurveInterval#(Float64) = (.start = 0.5, .end = 0.5)
    [
        testing.expect_error(
            .actual_result = [
                builder
                | declare_edge(
                    $&_, .curve = curve, .interval = invalid_interval, .start = a, .end = b
                )
            ]
            .expected_reason = ..invalid_parameter
        )!
    ]
    [
        testing.expect_error(
            .actual_result = [
                builder
                | declare_edge($&_, .curve = curve, .interval = first, .start = b, .end = a)
            ]
            .expected_reason = ..invalid_surface
        )!
    ]
    [
        testing.expect_error(
            .actual_result = [
                builder
                | declare_edge($&_, .curve = curve, .interval = first, .start = a, .end = a)
            ]
            .expected_reason = ..degenerate_face
        )!
    ]
    foreign_builder ::= BrepBuilder#(Float64)()!
    foreign ::= [
        declare_vertex(
            $&foreign_builder, .point = [g.circle_point(.circle = circle, .angle = 0.0)!]
        )!
    ]
    [
        testing.expect_error(
            .actual_result = [
                builder
                | declare_edge(
                    $&_, .curve = curve, .interval = first, .start = foreign, .end = b
                )
            ]
            .expected_reason = ..wrong_domain
        )!
    ]
    ab ::= builder | declare_edge($&_, .curve = curve, .interval = first, .start = a, .end = b)!
    ba ::= builder | declare_edge($&_, .curve = curve, .interval = last, .start = b, .end = a)!
    support: g.Surface#(Float64) = ..plane(
        .value = (.origin = basis.origin, .normal = basis.z)
    )
    surface ::= builder | declare_surface($&_, .surface = support)!
    p: PCurve#(Float64) = ..ellipse(
        .center = (.u = 0.0, .v = 0.0)
        .cosine = (.u = 2.0, .v = 0.0)
        .sine   = (.u = 0.0, .v = 2.0)
        .start  = 0.0
        .end    = 3.141592653589793
    )
    q: PCurve#(Float64) = ..ellipse(
        .center = (.u = 0.0, .v = 0.0)
        .cosine = (.u = 2.0, .v = 0.0)
        .sine   = (.u = 0.0, .v = 2.0)
        .start  = 3.141592653589793
        .end    = 6.283185307179586
    )
    repeated: [2]TrimUse#(Float64) = ((.edge = ab, .pcurve = p), (.edge = ab, .pcurve = p))
    lengths: [1]UIntNative = (2,)
    [
        testing.expect_error(
            .actual_result = declare_trimmed_face(
                $&builder
                .surface         = surface
                .boundaries      = view(&repeated)
                .contour_lengths = view(&lengths)
            )
            .expected_reason = ..nonmanifold_edge
        )!
    ]
    disconnected: [2]TrimUse#(Float64) = (
        (.edge = ab, .pcurve = p),
        (.edge = ba, .pcurve = q, .reversed = true)
    )
    [
        testing.expect_error(
            .actual_result = declare_trimmed_face(
                $&builder
                .surface         = surface
                .boundaries      = view(&disconnected)
                .contour_lengths = view(&lengths)
            )
            .expected_reason = ..inconsistent_orientation
        )!
    ]
    -- A cyclic change of loop anchor crosses the curve's period, without a seam.
    rotated: [2]TrimUse#(Float64) = ((.edge = ba, .pcurve = q), (.edge = ab, .pcurve = p))
    invalid_lengths: [2]UIntNative = (2, 1)
    [
        testing.expect_error(
            .actual_result = declare_trimmed_face(
                $&builder
                .surface         = surface
                .boundaries      = view(&rotated)
                .contour_lengths = view(&invalid_lengths)
            )
            .expected_reason = ..invalid_region_lengths
        )!
    ]
    [
        declare_trimmed_face(
            $&builder
            .surface         = surface
            .boundaries      = view(&rotated)
            .contour_lengths = view(&lengths)
        )!
    ]
    model ::= builder | finish_brep(~_, .require_closed = false)!
    testing.expect(entity_counts(&model).edges == 2 and entity_counts(&model).faces == 1)!
    [
        testing.expect(
            [
                geometry_storage_info(&model).intervals == 2
                and geometry_storage_info(&model).pcurves == 2
            ]
        )!
    ]
    [
        testing.expect(
            [face_contains_parameters(&model, .face = (.value = 0), .u = 0.0, .v = 0.0)!]
        )!
    ]
}

test model_arc_shared_edges_on_opposite_faces := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    -- Paired incidence on coincident annuli tests topology, not solid validity.
    model ::= _arc_annulus#(.Scalar: Float64)(.allocator = allocator, .close = true)!
    counts ::= entity_counts(&model)
    [
        testing.expect(
            [
                is_closed(&model).ok
                and counts.faces == 2
                and counts.edges == 4
                and counts.vertices == 4
            ]
        )!
    ]
    [
        testing.expect(
            [
                geometry_storage_info(&model).surfaces == 1
                and geometry_storage_info(&model).curves == 2
            ]
        )!
    ]
    i :: UIntNative = 0
    while i < counts.edges {
        id ::= i | convert#(.to: EdgeId)(_)
        edge ::= edge_info(&model, .edge = id)!
        match edge.second {
            ..none { [testing.fail()!] }
            ..some second {
                a ::= halfedge_info(&model, .halfedge = edge.first)!
                b ::= halfedge_info(&model, .halfedge = second.value)!
                testing.expect(a.reversed != b.reversed)!
            }
        }
        i = i + 1
    }
    reversed ::= reverse_orientation(&model)!
    [_validate_vertices(&reversed._topology, .allocator = allocator)!]
    [
        testing.expect(
            [face_contains_parameters(&reversed, .face = (.value = 0), .u = 2.0, .v = 0.0)!]
        )!
    ]
    [
        testing.expect(
            [
                [face_contains_parameters(&reversed, .face = (.value = 1), .u = 0.0, .v = 0.0)!]
                == false
            ]
        )!
    ]
}

test model_arc_unequal_intervals_cross_period := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    model ::= [
        _arc_annulus#(.Scalar: Float64)(
            .allocator = allocator, .phase = 0.875, .partition = 0.25
        )!
    ]
    first ::= edge_interval(&model, .edge = (.value = 0))!
    testing.expect(first.start == 0.875 and first.end == 1.125)!
    testing.expect(entity_counts(&model).vertices == 4 and entity_counts(&model).edges == 4)!
    for boundary in [face_loops(&model, .face = (.value = 0))!] {
        for use in [loop_halfedges(&model, .loop = boundary.id)!] {
            t :: Float64 = 0.0
            while t <= 1.0 {
                p ::= halfedge_point(&model, .halfedge = use.id, .parameter = t)!
                uv ::= halfedge_parameters(&model, .halfedge = use.id, .parameter = t)!
                q ::= [
                    g.surface_point(
                        .surface = [face_surface(&model, .face = (.value = 0))!]
                        .u       = uv.u
                        .v       = uv.v
                    )!
                ]
                [_trim_near_point(.a = p, .b = q, .tolerance = 0.000001)!]
                t = t + 0.125
            }
        }
    }
    inverted ::= reverse_orientation(&model)!
    [
        testing.expect(
            [face_contains_parameters(&inverted, .face = (.value = 0), .u = 2.0, .v = 0.0)!]
        )!
    ]
}
