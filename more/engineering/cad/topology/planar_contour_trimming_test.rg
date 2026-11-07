_mixed_planar_face := #(.Scalar: Type: Float) (
    .allocator   : Virtual#(Allocator),
    .hole_y      : Scalar      = 1.0,
    .hole_radius : Scalar      = 0.25,
    .bad_trim    : Bool        = false,
    .rotate      : Bool        = false,
    .renumber    : Bool        = false
) -> (.result: Errable#(Model#(Scalar), BrepErrors)) {
    builder ::= BrepBuilder#(Scalar)(.allocator = allocator)!
    plane: g.Plane#(Scalar) = (
        .origin = (0.0, 0.0, 0.0)
        .normal = (0.0, 0.0, 1.0)
    )
    support: g.Surface#(Scalar) = ..plane(.value = plane)
    surface ::= builder | declare_surface($&_, .surface = support, .allocator = allocator)!
    -- Work in the support chart: world X = v, world Y = -u.
    first_point :: g.Point#(Scalar) = (0.0, -3.0, 0.0)
    second_point :: g.Point#(Scalar) = (0.0, 3.0, 0.0)
    if renumber {
        first ::= first_point
        first_point = second_point
        second_point = first
    }
    a ::= builder | declare_vertex($&_, .point = first_point, .allocator = allocator)!
    b ::= builder | declare_vertex($&_, .point = second_point, .allocator = allocator)!
    if renumber {
        first ::= a
        a = b
        b = first
    }
    basis: g.Frame#(Scalar) = (
        .origin = plane.origin
        .x      = (0.0, -1.0, 0.0)
        .y      = (1.0, 0.0, 0.0)
        .z      = plane.normal
    )
    arc: Curve#(Scalar) = ..circle(.value = (.frame = basis, .radius = 3.0))
    line: Curve#(Scalar) = ..segment(
        .start = (0.0, 3.0, 0.0)
        .end   = (0.0, -3.0, 0.0)
    )
    c ::= builder | declare_curve($&_, .curve = arc, .allocator = allocator)!
    d ::= builder | declare_curve($&_, .curve = line, .allocator = allocator)!
    arc_interval: CurveInterval#(Scalar) = (.start = 0.0, .end = 0.5)
    line_interval: CurveInterval#(Scalar) = (.start = 0.0, .end = 1.0)
    e ::= declare_edge(
        $&builder
        .curve     = c
        .interval  = arc_interval
        .start     = a
        .end       = b
        .allocator = allocator
    )!
    f ::= declare_edge(
        $&builder
        .curve     = d
        .interval  = line_interval
        .start     = b
        .end       = a
        .allocator = allocator
    )!
    hole_frame: g.Frame#(Scalar) = (
        .origin = (hole_y, 0.0, 0.0)
        .x      = basis.x
        .y      = basis.y
        .z      = basis.z
    )
    hole: Curve#(Scalar) = ..circle(.value = (.frame = hole_frame, .radius = hole_radius))
    hcurve ::= builder | declare_curve($&_, .curve = hole, .allocator = allocator)!
    h ::= builder | declare_closed_edge($&_, .curve = hcurve, .allocator = allocator)!
    arc_trim: PCurve#(Scalar) = ..ellipse(
        .center = (.u = 0.0, .v = 0.0)
        .cosine = (.u = 3.0, .v = 0.0)
        .sine   = (.u = 0.0, .v = 3.0)
        .start  = 0.0
        .end    = 3.141592653589793
    )
    height :: Scalar = 0.0
    if bad_trim { height = 0.25 }
    line_trim: PCurve#(Scalar) = ..line(
        .start = (.u = -3.0, .v = height)
        .end   = (.u = 3.0, .v = height)
    )
    hole_trim: PCurve#(Scalar) = ..ellipse(
        .center = (.u = 0.0, .v = hole_y)
        .cosine = (.u = hole_radius, .v = 0.0)
        .sine   = (.u = 0.0, .v = hole_radius)
        .start  = 0.0
        .end    = 6.283185307179586
    )
    boundaries: [3]TrimUse#(Scalar) = (
        (.edge = e, .pcurve = arc_trim),
        (.edge = f, .pcurve = line_trim),
        (.edge = h, .pcurve = hole_trim, .reversed = true)
    )
    if rotate {
        first ::= boundaries[0]
        boundaries[0] = boundaries[1]
        boundaries[1] = first
    }
    lengths: [2]UIntNative = (2, 1)
    declare_trimmed_face(
        $&builder
        .surface         = surface
        .boundaries      = view(&boundaries)
        .contour_lengths = view(&lengths)
        .allocator       = allocator
    )!
    result = [builder | finish_brep(~_, .require_closed = false, .allocator = allocator)]
}

test model_mixed_planar_face_with_hole := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    model ::= _mixed_planar_face#(.Scalar: Float64)(.allocator = allocator)!
    inverse ::= reverse_orientation(&model)!
    rotated ::= [
        _mixed_planar_face#(.Scalar: Float64)(
            .allocator = allocator, .rotate = true, .renumber = true
        )!
    ]
    counts ::= entity_counts(&model)
    [
        testing.expect(
            [
                counts.vertices == 2
                and counts.edges == 3
                and counts.loops == 2
                and counts.faces == 1
            ]
        )!
    ]
    [
        testing.expect(
            [face_contains_parameters(&model, .face = (.value = 0), .u = 0.0, .v = 2.0)!]
        )!
    ]
    [
        testing.expect(
            [
                [face_contains_parameters(&model, .face = (.value = 0), .u = 0.0, .v = 1.0)!]
                == false
            ]
        )!
    ]
    [
        testing.expect(
            [
                [face_contains_parameters(&model, .face = (.value = 0), .u = 0.0, .v = -1.0)!]
                == false
            ]
        )!
    ]
    [
        testing.expect(
            [face_contains_parameters(&model, .face = (.value = 0), .u = 0.0, .v = 3.0)!]
        )!
    ]
    [
        testing.expect(
            [face_contains_parameters(&model, .face = (.value = 0), .u = 0.0, .v = 0.0)!]
        )!
    ]
    [
        testing.expect(
            [face_contains_parameters(&model, .face = (.value = 0), .u = 0.0, .v = 1.25)!]
        )!
    ]
    u :: Float64 = -3.5
    while u <= 3.5 {
        v :: Float64 = -0.5
        while v <= 3.5 {
            [
                testing.expect(
                    [
                        [face_contains_parameters(&model, .face = (.value = 0), .u = u, .v = v)!]
                        == [
                            face_contains_parameters(
                                &inverse, .face = (.value = 0), .u = u, .v = v
                            )!
                        ]
                    ]
                )!
            ]
            [
                testing.expect(
                    [
                        [face_contains_parameters(&model, .face = (.value = 0), .u = u, .v = v)!]
                        == [
                            face_contains_parameters(
                                &rotated, .face = (.value = 0), .u = u, .v = v
                            )!
                        ]
                    ]
                )!
            ]
            radial ::= hypot(.left = u, .right = v).result
            hole_distance ::= hypot(.left = u, .right = v - 1.0).result
            if radial < 2.999 and v > 0.001 and hole_distance > 0.251 {
                [
                    testing.expect(
                        [face_contains_parameters(&model, .face = (.value = 0), .u = u, .v = v)!]
                    )!
                ]
            }
            v = v + 0.25
        }
        u = u + 0.25
    }
    for loop in [face_loops(&model, .face = (.value = 0))!] {
        for use in [loop_halfedges(&model, .loop = loop.id)!] {
            t :: Float64 = 0.0
            while t <= 1.0 {
                uv ::= halfedge_parameters(&model, .halfedge = use.id, .parameter = t)!
                p ::= halfedge_point(&model, .halfedge = use.id, .parameter = t)!
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
}

test model_mixed_planar_face_float32_and_rejections := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    model ::= _mixed_planar_face#(.Scalar: Float32)(.allocator = allocator)!
    [
        testing.expect(
            [face_contains_parameters(&model, .face = (.value = 0), .u = 0.0, .v = 2.0)!]
        )!
    ]
    [
        testing.expect_error(
            .actual_result = _mixed_planar_face#(.Scalar: Float64)(
                .allocator = allocator, .bad_trim = true
            )
            .expected_reason = ..invalid_surface
        )!
    ]
    [
        testing.expect_error(
            .actual_result = _mixed_planar_face#(.Scalar: Float64)(
                .allocator = allocator, .hole_y = -1.0
            )
            .expected_reason = ..invalid_region_nesting
        )!
    ]
    [
        testing.expect_error(
            .actual_result = _mixed_planar_face#(.Scalar: Float64)(
                .allocator = allocator, .hole_y = 0.0
            )
            .expected_reason = ..intersecting_contours
        )!
    ]
    [
        testing.expect_error(
            .actual_result = _mixed_planar_face#(.Scalar: Float64)(
                .allocator = allocator, .hole_y = 3.0
            )
            .expected_reason = ..intersecting_contours
        )!
    ]
}
