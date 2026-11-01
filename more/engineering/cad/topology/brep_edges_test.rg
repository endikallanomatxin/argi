test model_ellipse_arc_rejections_leave_builder_usable := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    builder ::= BrepBuilder#(Float64)()!
    ellipse: g.Ellipse#(Float64) = (
        .center = (0.0, 0.0, 1.0)
        .cosine = (2.0, 0.0, 0.5)
        .sine   = (0.25, 1.0, 0.0)
    )
    curve: Curve#(Float64) = ..ellipse(.value = ellipse)
    id ::= builder | declare_curve($&_, .curve = curve)!
    a ::= [
        declare_vertex($&builder, .point = [g.ellipse_point(.ellipse = ellipse, .angle = 0.0)!])!
    ]
    b ::= [
        declare_vertex(
            $&builder
            .point = [g.ellipse_point(.ellipse = ellipse, .angle = 3.141592653589793)!]
        )!
    ]
    wrong ::= builder | declare_vertex($&_, .point = ellipse.center)!
    [
        testing.expect_error(
            .actual_result = declare_edge(
                $&builder
                .curve    = id
                .interval = (.start = 0.0, .end = 0.5)
                .start    = a
                .end      = wrong
            )
            .expected_reason = ..invalid_surface
        )!
    ]
    [
        testing.expect_error(
            .actual_result = declare_edge(
                $&builder
                .curve    = id
                .interval = (.start = 0.0, .end = 1.0)
                .start    = a
                .end      = b
            )
            .expected_reason = ..invalid_parameter
        )!
    ]
    other ::= BrepBuilder#(Float64)()!
    foreign ::= other | declare_vertex($&_, .point = ellipse.center)!
    [
        testing.expect_error(
            .actual_result = declare_edge(
                $&builder
                .curve    = id
                .interval = (.start = 0.0, .end = 0.5)
                .start    = a
                .end      = foreign
            )
            .expected_reason = ..wrong_domain
        )!
    ]
    edge ::= [
        [
            builder
            | declare_edge(
                $&_, .curve = id, .interval = (.start = 0.0, .end = 0.5), .start = a, .end = b
            )
        ]!
    ]
    [
        testing.expect([[idx.resolve_index(.domain = &builder._domain, .index = edge)!] == 0])!
    ]
    [
        testing.expect(
            [
                Indexable#(
                    DynamicArray#(CurveInterval#(Float64))
                ).length(&builder._geometry.intervals).count
                == 1
            ]
        )!
    ]
}

test model_segment_edge_interval_and_planar_correspondence := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    builder ::= BrepBuilder#(Float64)()!
    curve: Curve#(Float64) = ..segment(
        .start = (0.0, 0.0, 0.0)
        .end   = (4.0, 0.0, 0.0)
    )
    id ::= builder | declare_curve($&_, .curve = curve)!
    a ::= builder | declare_vertex($&_, .point = (1.0, 0.0, 0.0))!
    b ::= builder | declare_vertex($&_, .point = (3.0, 0.0, 0.0))!
    edge ::= [
        declare_edge(
            $&builder
            .curve    = id
            .interval = (.start = 0.25, .end = 0.75)
            .start    = a
            .end      = b
        )!
    ]
    [
        testing.expect([[idx.resolve_index(.domain = &builder._domain, .index = edge)!] == 0])!
    ]
    plane: g.Plane#(Float64) = (
        .origin = (0.0, 0.0, 0.0)
        .normal = (0.0, 0.0, 1.0)
    )
    -- This plane's generated x axis is -Y, and its y axis is X.
    trim: PCurve#(Float64) = ..line(.start = (.u = 0.0, .v = 1.0), .end = (.u = 0.0, .v = 3.0))
    [
        _certify_planar_trim(
            .plane     = plane
            .curve     = curve
            .interval  = (.start = 0.25, .end = 0.75)
            .pcurve    = trim
            .tolerance = 0.000001
        )!
    ]
    [
        testing.expect_error(
            .actual_result = _certify_planar_trim(
                .plane     = plane
                .curve     = curve
                .interval  = (.start = 0.0, .end = 1.0)
                .pcurve    = trim
                .tolerance = 0.000001
            )
            .expected_reason = ..invalid_surface
        )!
    ]
    [
        testing.expect_error(
            .actual_result = declare_edge(
                $&builder
                .curve    = id
                .interval = (.start = -0.25, .end = 0.5)
                .start    = a
                .end      = b
            )
            .expected_reason = ..invalid_parameter
        )!
    ]
}
