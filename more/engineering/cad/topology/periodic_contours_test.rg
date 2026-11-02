_partitioned_oblique_cylinder := #(.Scalar: Type: Float) (
    .allocator      : Virtual#(Allocator),
    .phase          : Scalar      = 0.875,
    .bad_second     : Bool        = false,
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
    tau: Scalar = 6.283185307179586
    middle ::= phase + 0.25
    end ::= phase + 1.0
    first_interval: CurveInterval#(Scalar) = (.start = phase, .end = middle)
    last_interval: CurveInterval#(Scalar) = (.start = middle, .end = end)
    a ::= declare_vertex(
        $&builder
        .point     = g.ellipse_point(.ellipse = lower, .angle = [phase * tau])!
        .allocator = allocator
    )!
    b ::= declare_vertex(
        $&builder
        .point     = g.ellipse_point(.ellipse = lower, .angle = [middle * tau])!
        .allocator = allocator
    )!
    c ::= declare_vertex(
        $&builder
        .point     = g.ellipse_point(.ellipse = upper, .angle = [phase * tau])!
        .allocator = allocator
    )!
    d ::= declare_vertex(
        $&builder
        .point     = g.ellipse_point(.ellipse = upper, .angle = [middle * tau])!
        .allocator = allocator
    )!
    bottom_a ::= declare_edge(
        $&builder
        .curve     = lc
        .interval  = first_interval
        .start     = a
        .end       = b
        .allocator = allocator
    )!
    bottom_b ::= declare_edge(
        $&builder
        .curve     = lc
        .interval  = last_interval
        .start     = b
        .end       = a
        .allocator = allocator
    )!
    top_a ::= declare_edge(
        $&builder
        .curve     = uc
        .interval  = first_interval
        .start     = c
        .end       = d
        .allocator = allocator
    )!
    top_b ::= declare_edge(
        $&builder
        .curve     = uc
        .interval  = last_interval
        .start     = d
        .end       = c
        .allocator = allocator
    )!
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
    high_b ::= _test_pcurve_interval(
        .curve = high, .start = middle * tau, .end = end * tau
    ).result
    high_a ::= _test_pcurve_interval(
        .curve = high, .start = phase * tau, .end = middle * tau
    ).result
    if bad_second {
        bad_high: PCurve#(Scalar) = ..harmonic(
            .origin = (.u = 0.0, .v = height + 1.0)
            .linear = (.u = 1.0, .v = 0.0)
            .cosine = (.u = 0.0, .v = slope * 2.0)
            .sine   = (.u = 0.0, .v = 0.0)
            .start  = phase * tau
            .end    = middle * tau
        )
        high_a = bad_high
    }
    boundaries: [4]TrimUse#(Scalar) = (
        (
            .edge   = bottom_a
            .pcurve = _test_pcurve_interval(
                .curve = low, .start = phase * tau, .end = [middle * tau]
            ).result
        ),
        (
            .edge   = bottom_b
            .pcurve = _test_pcurve_interval(
                .curve = low, .start = middle * tau, .end = [end * tau]
            ).result
        ),
        (.edge = top_b, .pcurve = high_b, .reversed = true),
        (
            .edge     = top_a
            .pcurve   = high_a
            .reversed = true
        )
    )
    lengths: [2]UIntNative = (2, 2)
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
    luses: [2]TrimUse#(Scalar) = (
        (
            .edge   = bottom_b
            .pcurve = _test_pcurve_interval(
                .curve = ltrim, .start = middle * tau, .end = [end * tau]
            ).result
            .reversed = true
        ),
        (
            .edge   = bottom_a
            .pcurve = _test_pcurve_interval(
                .curve = ltrim, .start = phase * tau, .end = [middle * tau]
            ).result
            .reversed = true
        )
    )
    uuses: [2]TrimUse#(Scalar) = (
        (
            .edge   = top_a
            .pcurve = _test_pcurve_interval(
                .curve = utrim, .start = phase * tau, .end = [middle * tau]
            ).result
        ),
        (
            .edge   = top_b
            .pcurve = _test_pcurve_interval(
                .curve = utrim, .start = middle * tau, .end = [end * tau]
            ).result
        )
    )
    one: [1]UIntNative = (2,)
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

_test_pcurve_interval := #(.Scalar: Type: Float) (
    .curve: PCurve#(Scalar), .start: Scalar, .end: Scalar
) -> (.result: PCurve#(Scalar)) {
    match curve {
        ..line line { result = ..line(.start = line.start, .end = line.end) }
        ..ellipse e {
            result = ..ellipse(
                .center = e.center
                .cosine = e.cosine
                .sine   = e.sine
                .start  = start
                .end    = end
            )
        }
        ..harmonic h {
            result = ..harmonic(
                .origin = h.origin
                .linear = h.linear
                .cosine = h.cosine
                .sine   = h.sine
                .start  = start
                .end    = end
            )
        }
    }
}

test model_partitioned_cylinder_preserves_geometry_and_incidence := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    model ::= _partitioned_oblique_cylinder#(.Scalar: Float64)(.allocator = allocator)!
    reference ::= _oblique_cylinder#(.Scalar: Float64)(.allocator = allocator)!
    counts ::= entity_counts(&model)
    testing.expect(is_closed(&model).ok and counts.vertices == 4 and counts.edges == 4)!
    testing.expect(counts.faces == 3 and counts.loops == 4 and counts.halfedges == 8)!
    storage ::= geometry_storage_info(&model)
    testing.expect(storage.circles == 1 and storage.ellipses == 1)!
    inverted ::= reverse_orientation(&model)!
    [_validate_vertices(&model._topology, .allocator = allocator)!]
    [_validate_vertices(&inverted._topology, .allocator = allocator)!]
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
                    r ::= halfedge_point(&inverted, .halfedge = use.id, .parameter = [1.0 - t])!
                    [_trim_near_point(.a = p, .b = q, .tolerance = 0.000001)!]
                    [_trim_near_point(.a = p, .b = r, .tolerance = 0.000001)!]
                    t = t + 0.125
                }
            }
        }
        u :: Float64 = -7.0
        while u < 7.0 {
            v :: Float64 = -1.0
            while v <= 4.0 {
                inside ::= face_contains_parameters(&model, .face = face, .u = u, .v = v)!
                [
                    testing.expect(
                        [
                            inside
                            == [
                                face_contains_parameters(
                                    &reference, .face = face, .u = u, .v = v
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
                                face_contains_parameters(
                                    &inverted, .face = face, .u = u, .v = v
                                )!
                            ]
                        ]
                    )!
                ]
                v = v + 0.5
            }
            u = u + 0.5
        }
        i = i + 1
    }
}

test model_partitioned_cylinder_float32_and_all_arc_certificates := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    model ::= _partitioned_oblique_cylinder#(.Scalar: Float32)(.allocator = allocator)!
    testing.expect(is_closed(&model).ok and entity_counts(&model).vertices == 4)!
    rotated ::= [
        _partitioned_oblique_cylinder#(.Scalar: Float64)(.allocator = allocator, .phase = 0.25)!
    ]
    testing.expect(is_closed(&rotated).ok)!
    [
        testing.expect_error(
            .actual_result = _partitioned_oblique_cylinder#(.Scalar: Float64)(
                .allocator = allocator, .bad_second = true
            )
            .expected_reason = ..invalid_surface
        )!
    ]
}

test model_periodic_contour_rejects_gaps_overlap_and_multiple_turns := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    uses ::= DynamicArray#(_ResolvedTrim#(Float64))(.capacity = 2)!
    pcurve: PCurve#(Float64) = ..ellipse(
        .center = (.u = 0.0, .v = 0.0)
        .cosine = (.u = 1.0, .v = 0.0)
        .sine   = (.u = 0.0, .v = 1.0)
        .start  = 0.0
        .end    = 3.141592653589793
    )
    first: _ResolvedTrim#(Float64) = (
        .edge        = (.value = 0)
        .origin      = ..none
        .destination = ..none
        .curve       = (.value = 0)
        .interval    = (.start = 0.0, .end = 0.5)
        .pcurve      = pcurve
        .reversed    = false
    )
    second: _ResolvedTrim#(Float64) = (
        .edge        = (.value = 1)
        .origin      = ..none
        .destination = ..none
        .curve       = (.value = 0)
        .interval    = (.start = 0.5, .end = 1.0)
        .pcurve      = pcurve
        .reversed    = false
    )
    push_assume_capacity($&uses, .value = first)
    push_assume_capacity($&uses, .value = second)
    [_admit_periodic_contour(.uses = &uses, .start = 0, .count = 2)!]
    second.interval = (.start = 0.75, .end = 1.25)
    {
        slot ::= get_mutable_reference($&uses, .index = 1)!
        slot&= second
    }
    [
        testing.expect_error(
            .actual_result   = _admit_periodic_contour(.uses = &uses, .start = 0, .count = 2)
            .expected_reason = ..unsupported_parameterization
        )!
    ]
    second.interval = (.start = 0.25, .end = 0.75)
    {
        slot ::= get_mutable_reference($&uses, .index = 1)!
        slot&= second
    }
    [
        testing.expect_error(
            .actual_result   = _admit_periodic_contour(.uses = &uses, .start = 0, .count = 2)
            .expected_reason = ..unsupported_parameterization
        )!
    ]
    second.interval = (.start = 0.5, .end = 1.5)
    {
        slot ::= get_mutable_reference($&uses, .index = 1)!
        slot&= second
    }
    [
        testing.expect_error(
            .actual_result   = _admit_periodic_contour(.uses = &uses, .start = 0, .count = 2)
            .expected_reason = ..unsupported_parameterization
        )!
    ]
    second.interval = (.start = 0.5, .end = 1.0)
    second.curve = (.value = 1)
    {
        slot ::= get_mutable_reference($&uses, .index = 1)!
        slot&= second
    }
    [
        testing.expect_error(
            .actual_result   = _admit_periodic_contour(.uses = &uses, .start = 0, .count = 2)
            .expected_reason = ..unsupported_boundary
        )!
    ]
}
