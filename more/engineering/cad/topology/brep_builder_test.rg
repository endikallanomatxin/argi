_brep_hemisphere := #(.Scalar: Type: Float) (
    .allocator: Virtual#(Allocator), .north: Bool = true
) -> (.result: Errable#(Model#(Scalar), BrepErrors)) {
    builder ::= BrepBuilder#(Scalar)(.allocator = allocator)!
    basis ::= g.frame#(Scalar)(.origin = (0.0, 0.0, 0.0), .axis = (0.0, 0.0, 1.0))!
    spherical_support: g.Surface#(Scalar) = ..sphere(.frame = basis, .radius = 2.0)
    sphere ::= [
        builder
        | declare_surface($&_, .surface = spherical_support, .allocator = allocator)!
    ]
    plane: g.Plane#(Scalar) = (.origin = basis.origin, .normal = basis.z)
    planar_support: g.Surface#(Scalar) = ..plane(.value = plane)
    cap ::= builder | declare_surface($&_, .surface = planar_support, .allocator = allocator)!
    curve: Curve#(Scalar) = ..circle(.value = (.frame = basis, .radius = 2.0))
    support ::= builder | declare_curve($&_, .curve = curve, .allocator = allocator)!
    edge ::= builder | declare_closed_edge($&_, .curve = support, .allocator = allocator)!
    latitude: PCurve#(Scalar) = ..line(
        .start = (.u = 0.0, .v = 0.0)
        .end   = (.u = 6.283185307179586, .v = 0.0)
    )
    disk: PCurve#(Scalar) = ..ellipse(
        .center = (.u = 0.0, .v = 0.0)
        .cosine = (.u = 2.0, .v = 0.0)
        .sine   = (.u = 0.0, .v = 2.0)
        .start  = 0.0
        .end    = 6.283185307179586
    )
    sphere_use: TrimUse#(Scalar) = (
        .edge     = edge
        .pcurve   = latitude
        .reversed = [north == false]
    )
    cap_use: TrimUse#(Scalar) = (.edge = edge, .pcurve = disk, .reversed = north)
    sphere_uses: [1]TrimUse#(Scalar) = (sphere_use,)
    cap_uses: [1]TrimUse#(Scalar) = (cap_use,)
    lengths: [1]UIntNative = (1,)
    declare_trimmed_face(
        $&builder
        .surface         = sphere
        .boundaries      = view(&sphere_uses)
        .contour_lengths = view(&lengths)
        .allocator       = allocator
    )!
    declare_trimmed_face(
        $&builder
        .surface         = cap
        .reversed        = north
        .boundaries      = view(&cap_uses)
        .contour_lengths = view(&lengths)
        .allocator       = allocator
    )!
    model ::= builder | finish_brep(~_, .allocator = allocator)!
    result = ..ok ~model
}

test model_brep_hemisphere_shared_circle := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    model ::= [
        _brep_hemisphere#(.Scalar: Float64)(
            .allocator = allocator
        )!
    ]
    counts ::= entity_counts(&model)
    testing.expect(counts.vertices == 0 and counts.edges == 1 and counts.faces == 2)!
    testing.expect(counts.loops == 2 and counts.halfedges == 2 and is_closed(&model).ok)!
    [
        testing.expect([[face_info(&model, .face = (.value = 0))!].reversed == false])!
    ]
    testing.expect([face_info(&model, .face = (.value = 1))!].reversed)!
    testing.expect(geometry_storage_info(&model).curves == 1)!
    [
        testing.expect(
            [face_contains_parameters(&model, .face = (.value = 0), .u = 0.0, .v = 1.0)!]
        )!
    ]
    [
        testing.expect(
            [face_contains_parameters(&model, .face = (.value = 0), .u = 12.0, .v = 1.0)!]
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
            [face_contains_parameters(&model, .face = (.value = 1), .u = 0.0, .v = 0.0)!]
        )!
    ]
    [
        testing.expect(
            [
                [face_contains_parameters(&model, .face = (.value = 1), .u = 3.0, .v = 0.0)!]
                == false
            ]
        )!
    ]
    t :: Float64 = 0.0
    while t <= 1.0 {
        a ::= halfedge_point(&model, .halfedge = (.value = 0), .parameter = t)!
        b ::= halfedge_point(&model, .halfedge = (.value = 1), .parameter = 1.0 - t)!
        [_trim_near_point(.a = a, .b = b, .tolerance = 0.000001)!]
        uv ::= halfedge_parameters(&model, .halfedge = (.value = 0), .parameter = t)!
        spherical ::= [
            g.surface_point(
                .surface = [face_surface(&model, .face = (.value = 0))!], .u = uv.u, .v = uv.v
            )!
        ]
        [_trim_near_point(.a = a, .b = spherical, .tolerance = 0.000001)!]
        disk_uv ::= halfedge_parameters(&model, .halfedge = (.value = 1), .parameter = 1.0 - t)!
        planar ::= [
            g.surface_point(
                .surface = [face_surface(&model, .face = (.value = 1))!]
                .u       = disk_uv.u
                .v       = disk_uv.v
            )!
        ]
        [_trim_near_point(.a = a, .b = planar, .tolerance = 0.000001)!]
        t = t + 0.125
    }
}

test model_brep_hemisphere_float32 := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    model ::= [
        _brep_hemisphere#(.Scalar: Float32)(
            .allocator = allocator
        )!
    ]
    testing.expect(entity_counts(&model).vertices == 0 and is_closed(&model).ok)!
    uv ::= halfedge_parameters(&model, .halfedge = (.value = 0), .parameter = 0.5)!
    testing.expect(uv.u > 3.14 and uv.u < 3.15 and uv.v == 0.0)!
}

test model_brep_hemisphere_complementary_region := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    model ::= _brep_hemisphere#(.Scalar: Float64)(.allocator = allocator, .north = false)!
    testing.expect(is_closed(&model).ok)!
    [
        testing.expect(
            [face_contains_parameters(&model, .face = (.value = 0), .u = 0.0, .v = -1.0)!]
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
        testing.expect([[face_info(&model, .face = (.value = 0))!].reversed == false])!
    ]
    [
        testing.expect([[face_info(&model, .face = (.value = 1))!].reversed == false])!
    ]
}

test model_brep_trim_rejection_preserves_builder := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    builder ::= BrepBuilder#(Float64)()!
    basis ::= [
        g.frame#(Float64)(.origin = (0.0, 0.0, 0.0), .axis = (0.0, 0.0, 1.0))!
    ]
    support: g.Surface#(Float64) = ..plane(
        .value = (.origin = basis.origin, .normal = basis.z)
    )
    plane ::= builder | declare_surface($&_, .surface = support)!
    circle: Curve#(Float64) = ..circle(.value = (.frame = basis, .radius = 2.0))
    curve ::= builder | declare_curve($&_, .curve = circle)!
    [
        testing.expect_error(
            .actual_result = [
                builder
                | declare_closed_edge(
                    $&_, .curve = curve, .interval = (.start = 0.0, .end = 0.5)
                )
            ]
            .expected_reason = ..invalid_parameter
        )!
    ]
    edge ::= builder | declare_closed_edge($&_, .curve = curve)!
    disk: PCurve#(Float64) = ..ellipse(
        .center = (.u = 0.0, .v = 0.0)
        .cosine = (.u = 2.0, .v = 0.0)
        .sine   = (.u = 0.0, .v = 2.0)
        .start  = 0.0
        .end    = 6.283185307179586
    )
    displaced: PCurve#(Float64) = ..ellipse(
        .center = (.u = 1.0, .v = 0.0)
        .cosine = (.u = 2.0, .v = 0.0)
        .sine   = (.u = 0.0, .v = 2.0)
        .start  = 0.0
        .end    = 6.283185307179586
    )
    lengths: [1]UIntNative = (1,)
    invalid: TrimUse#(Float64) = (.edge = edge, .pcurve = displaced)
    invalid_uses: [1]TrimUse#(Float64) = (invalid,)
    [
        testing.expect_error(
            .actual_result = declare_trimmed_face(
                $&builder
                .surface         = plane
                .boundaries      = view(&invalid_uses)
                .contour_lengths = view(&lengths)
            )
            .expected_reason = ..invalid_surface
        )!
    ]
    wrong: TrimUse#(Float64) = (.edge = edge, .pcurve = disk, .reversed = true)
    wrong_uses: [1]TrimUse#(Float64) = (wrong,)
    [
        testing.expect_error(
            .actual_result = declare_trimmed_face(
                $&builder
                .surface         = plane
                .boundaries      = view(&wrong_uses)
                .contour_lengths = view(&lengths)
            )
            .expected_reason = ..inconsistent_orientation
        )!
    ]
    use: TrimUse#(Float64) = (.edge = edge, .pcurve = disk)
    use_uses: [1]TrimUse#(Float64) = (use,)
    [
        declare_trimmed_face(
            $&builder
            .surface         = plane
            .boundaries      = view(&use_uses)
            .contour_lengths = view(&lengths)
        )!
    ]
    [
        testing.expect_error(
            .actual_result = declare_trimmed_face(
                $&builder
                .surface         = plane
                .boundaries      = view(&use_uses)
                .contour_lengths = view(&lengths)
            )
            .expected_reason = ..inconsistent_orientation
        )!
    ]
    model ::= builder | finish_brep(~_, .require_closed = false)!
    counts ::= entity_counts(&model)
    testing.expect(counts.faces == 1 and counts.loops == 1 and counts.halfedges == 1)!
    testing.expect(is_closed(&model).ok == false)!
    testing.expect(geometry_storage_info(&model).pcurves == 1)!
}
