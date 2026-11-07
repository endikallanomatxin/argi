_plane_ellipse_pcurve := #(.Scalar: Type: Float) (
    .plane: g.Plane#(Scalar), .ellipse: g.Ellipse#(Scalar)
) -> (.result: Errable#(PCurve#(Scalar), BrepErrors)) {
    frame ::= g.frame(.origin = plane.origin, .axis = plane.normal)!
    offset ::= g.between(.from = plane.origin, .to = ellipse.center).result
    result = ..ok ..ellipse(
        .center = (
            .u = g.dot(.left = frame.x, .right = offset).value
            .v = g.dot(.left = frame.y, .right = offset).value
        )
        .cosine = (
            .u = g.dot(.left = frame.x, .right = ellipse.cosine).value
            .v = g.dot(.left = frame.y, .right = ellipse.cosine).value
        )
        .sine = (
            .u = g.dot(.left = frame.x, .right = ellipse.sine).value
            .v = g.dot(.left = frame.y, .right = ellipse.sine).value
        )
        .start = 0.0
        .end   = 6.283185307179586
    )
}

_oblique_cylinder := #(.Scalar: Type: Float) (
    .allocator      : Virtual#(Allocator),
    .height         : Scalar      = 3.0,
    .slope          : Scalar      = 0.25,
    .geometry_slope : Scalar      = 0.25
) -> (.result: Errable#(Model#(Scalar), BrepErrors)) {
    builder ::= BrepBuilder#(Scalar)(.allocator = allocator)!
    frame: g.Frame#(Scalar) = (
        .origin = (0.0, 0.0, 0.0)
        .x      = (1.0, 0.0, 0.0)
        .y      = (0.0, 1.0, 0.0)
        .z      = (0.0, 0.0, 1.0)
    )
    cylinder: g.Surface#(Scalar) = ..cylinder(.frame = frame, .radius = 2.0)
    side ::= builder | declare_surface($&_, .surface = cylinder, .allocator = allocator)!
    lower: g.Ellipse#(Scalar) = (
        .center = frame.origin
        .cosine = (2.0, 0.0, 0.0)
        .sine   = (0.0, 2.0, 0.0)
    )
    upper: g.Ellipse#(Scalar) = (
        .center = (0.0, 0.0, height)
        .cosine = (2.0, 0.0, geometry_slope * 2.0)
        .sine   = (0.0, 2.0, 0.0)
    )
    lower_curve: Curve#(Scalar) = ..circle(.value = (.frame = frame, .radius = 2.0))
    upper_curve: Curve#(Scalar) = ..ellipse(.value = upper)
    lc ::= builder | declare_curve($&_, .curve = lower_curve, .allocator = allocator)!
    uc ::= builder | declare_curve($&_, .curve = upper_curve, .allocator = allocator)!
    bottom ::= builder | declare_closed_edge($&_, .curve = lc, .allocator = allocator)!
    top ::= builder | declare_closed_edge($&_, .curve = uc, .allocator = allocator)!
    low: PCurve#(Scalar) = ..harmonic(
        .origin = (.u = 0.0, .v = 0.0)
        .linear = (.u = 1.0, .v = 0.0)
        .cosine = (.u = 0.0, .v = 0.0)
        .sine   = (.u = 0.0, .v = 0.0)
        .start  = 0.0
        .end    = 6.283185307179586
    )
    high: PCurve#(Scalar) = ..harmonic(
        .origin = (.u = 0.0, .v = height)
        .linear = (.u = 1.0, .v = 0.0)
        .cosine = (.u = 0.0, .v = slope * 2.0)
        .sine   = (.u = 0.0, .v = 0.0)
        .start  = 0.0
        .end    = 6.283185307179586
    )
    boundaries: [2]TrimUse#(Scalar) = (
        (.edge = bottom, .pcurve = low),
        (.edge = top, .pcurve = high, .reversed = true)
    )
    lengths: [2]UIntNative = (1, 1)
    declare_trimmed_face(
        $&builder
        .surface         = side
        .boundaries      = view(&boundaries)
        .contour_lengths = view(&lengths)
        .allocator       = allocator
    )!
    lower_plane: g.Plane#(Scalar) = (.origin = lower.center, .normal = frame.z)
    upper_plane: g.Plane#(Scalar) = (
        .origin = upper.center
        .normal = (
            .x = [0.0 - geometry_slope]
            .y = 0.0
            .z = 1.0
        )
    )
    lsurface: g.Surface#(Scalar) = ..plane(.value = lower_plane)
    usurface: g.Surface#(Scalar) = ..plane(.value = upper_plane)
    lp ::= builder | declare_surface($&_, .surface = lsurface, .allocator = allocator)!
    up ::= builder | declare_surface($&_, .surface = usurface, .allocator = allocator)!
    ltrim ::= _plane_ellipse_pcurve(.plane = lower_plane, .ellipse = lower)!
    utrim ::= _plane_ellipse_pcurve(.plane = upper_plane, .ellipse = upper)!
    luses: [1]TrimUse#(Scalar) = ((.edge = bottom, .pcurve = ltrim, .reversed = true),)
    uuses: [1]TrimUse#(Scalar) = ((.edge = top, .pcurve = utrim),)
    one: [1]UIntNative = (1,)
    declare_trimmed_face(
        $&builder
        .surface         = lp
        .boundaries      = view(&luses)
        .contour_lengths = view(&one)
        .reversed        = true
        .allocator       = allocator
    )!
    declare_trimmed_face(
        $&builder
        .surface         = up
        .boundaries      = view(&uuses)
        .contour_lengths = view(&one)
        .allocator       = allocator
    )!
    model ::= builder | finish_brep(~_, .allocator = allocator)!
    result = ..ok ~model
}

test model_oblique_cylinder_shared_elliptic_boundaries := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    model ::= _oblique_cylinder#(.Scalar: Float64)(.allocator = allocator)!
    counts ::= entity_counts(&model)
    [
        testing.expect(
            [
                is_closed(&model).ok
                and counts.vertices == 0
                and counts.edges == 2
                and counts.faces == 3
            ]
        )!
    ]
    testing.expect(counts.loops == 4 and counts.halfedges == 4)!
    [
        testing.expect(
            [
                geometry_storage_info(&model).ellipses == 1
                and geometry_storage_info(&model).circles == 1
            ]
        )!
    ]
    i :: UIntNative = 0
    while i < counts.faces {
        face ::= i | convert#(.to: FaceId)(_)
        for boundary in [face_loops(&model, .face = face)!] {
            for use in [loop_halfedges(&model, .loop = boundary.id)!] {
                t :: Float64 = 0.0
                while t <= 1.0 {
                    p ::= halfedge_point(&model, .halfedge = use.id, .parameter = t)!
                    uv ::= halfedge_parameters(&model, .halfedge = use.id, .parameter = t)!
                    q ::= [
                        g.surface_point(
                            .surface = [face_surface(&model, .face = face)!]
                            .u       = uv.u
                            .v       = uv.v
                        )!
                    ]
                    [_trim_near_point(.a = p, .b = q, .tolerance = 0.000001)!]
                    t = t + 0.125
                }
            }
        }
        i = i + 1
    }
    [
        testing.expect(
            [face_contains_parameters(&model, .face = (.value = 0), .u = 0.0, .v = 3.25)!]
        )!
    ]
    [
        testing.expect(
            [
                [
                    face_contains_parameters(
                        &model, .face = (.value = 0), .u = 3.141592653589793, .v = 3.25
                    )!
                ]
                == false
            ]
        )!
    ]
    inverted ::= reverse_orientation(&model)!
    testing.expect(geometry_storage_info(&inverted).ellipses == 1)!
    original_point ::= halfedge_point(&model, .halfedge = (.value = 1), .parameter = 0.25)!
    inverted_point ::= halfedge_point(&inverted, .halfedge = (.value = 1), .parameter = 0.75)!
    [_trim_near_point(.a = original_point, .b = inverted_point, .tolerance = 0.000001)!]
    [
        testing.expect(
            [face_contains_parameters(&inverted, .face = (.value = 2), .u = 0.0, .v = 0.0)!]
        )!
    ]
    [
        testing.expect(
            [
                face_contains_parameters(
                    &inverted, .face = (.value = 0), .u = 6.283185307179586, .v = 3.25
                )!
            ]
        )!
    ]
    [_validate_vertices(&inverted._topology, .allocator = allocator)!]
}

test model_oblique_cylinder_float32_and_rejections := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    model ::= _oblique_cylinder#(.Scalar: Float32)(.allocator = allocator)!
    testing.expect(is_closed(&model).ok and entity_counts(&model).edges == 2)!
    [
        testing.expect_error(
            .actual_result = _oblique_cylinder#(.Scalar: Float64)(
                .allocator = allocator, .slope = 0.5
            )
            .expected_reason = ..invalid_surface
        )!
    ]
    [
        testing.expect_error(
            .actual_result = _oblique_cylinder#(.Scalar: Float64)(
                .allocator = allocator, .height = 0.25
            )
            .expected_reason = ..invalid_region_nesting
        )!
    ]
    [
        testing.expect_error(
            .actual_result = _oblique_cylinder#(.Scalar: Float64)(
                .allocator = allocator, .height = 0.5
            )
            .expected_reason = ..numerical_ambiguity
        )!
    ]
}
