test geometry_orientation_rejects_uncertain_sign := (.system: System) -> !() {
    a: _RegionPoint#(Float64) = (0.0, 0.0)
    b: _RegionPoint#(Float64) = (1.0, 1.0)
    p: _RegionPoint#(Float64) = (2.0, 2.0000000000000004)
    [
        testing.expect_error(
            .expected_reason = ..numerical_ambiguity
            .actual_result   = _region_orientation(
                .a = a, .b = b, .p = p, .resolution = _float_resolution#(Float64)().value
            )
        )!
    ]
}

test geometry_orientation_handles_axis_collinearity := (.system: System) -> !() {
    a: _RegionPoint#(Float32) = (0.0, 2.0)
    b: _RegionPoint#(Float32) = (4.0, 2.0)
    p: _RegionPoint#(Float32) = (6.0, 2.0)
    [
        testing.expect(
            [
                [
                    _region_orientation(
                        .a          = a
                        .b          = b
                        .p          = p
                        .resolution = _float_resolution#(Float32)().value
                    )!
                ]
                == 0
            ]
        )!
    ]
}

test geometry_orientation_sign_and_reversal := (.system: System) -> !() {
    a: _RegionPoint#(Float64) = (0.0, 0.0)
    b: _RegionPoint#(Float64) = (1.0e200, 0.0)
    p: _RegionPoint#(Float64) = (0.0, 1.0e200)
    [
        testing.expect(
            [
                [
                    _region_orientation(
                        .a          = a
                        .b          = b
                        .p          = p
                        .resolution = _float_resolution#(Float64)().value
                    )!
                ]
                == 1
            ]
        )!
    ]
    [
        testing.expect(
            [
                [
                    _region_orientation(
                        .a          = b
                        .b          = a
                        .p          = p
                        .resolution = _float_resolution#(Float64)().value
                    )!
                ]
                == -1
            ]
        )!
    ]
}

test geometry_containment_propagates_uncertainty := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)

    points ::= DynamicArray#(_RegionPoint#(Float64))(.allocator = allocator)!
    [push($&points, .value = (0.0, 0.0), .allocator = allocator)!]
    [push($&points, .value = (2.0, 2.0), .allocator = allocator)!]
    [push($&points, .value = (0.0, 2.0), .allocator = allocator)!]
    [
        testing.expect_error(
            .expected_reason = ..numerical_ambiguity
            .actual_result   = _region_contains(
                .points     = &points
                .start      = 0
                .count      = 3
                .point      = (1.0, 1.0000000000000002)
                .resolution = _float_resolution#(Float64)().value
            )
        )!
    ]
}

test geometry_area_rejects_cancellation := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)

    points ::= DynamicArray#(_RegionPoint#(Float64))(.allocator = allocator)!
    [push($&points, .value = (0.0, 0.0), .allocator = allocator)!]
    [push($&points, .value = (1.0, 1.0), .allocator = allocator)!]
    [push($&points, .value = (2.0, 2.0000000000000004), .allocator = allocator)!]
    [
        testing.expect_error(
            .expected_reason = ..numerical_ambiguity
            .actual_result   = _region_area_positive(.points = &points, .start = 0, .count = 3)
        )!
    ]
}

test geometry_intersection_separates_contact_and_crossing := (.system: System) -> !() {
    a: _RegionPoint#(Float64) = (0.0, 0.0)
    b: _RegionPoint#(Float64) = (2.0, 2.0)
    c: _RegionPoint#(Float64) = (0.0, 2.0)
    d: _RegionPoint#(Float64) = (2.0, 0.0)
    [
        testing.expect(
            [
                _region_segments_touch(
                    .a          = a
                    .b          = b
                    .c          = c
                    .d          = d
                    .tolerance  = 0.000001
                    .resolution = _float_resolution#(Float64)().value
                )!
            ]
        )!
    ]
    far: _RegionPoint#(Float64) = (3.0, 3.0)
    farther: _RegionPoint#(Float64) = (4.0, 4.0)
    [
        testing.expect(
            [
                [
                    _region_segments_touch(
                        .a          = a
                        .b          = b
                        .c          = far
                        .d          = farther
                        .tolerance  = 0.000001
                        .resolution = _float_resolution#(Float64)().value
                    )!
                ]
                == false
            ]
        )!
    ]
    near: _RegionPoint#(Float64) = (2.0000001, 2.0000001)
    [
        testing.expect(
            [
                _region_segments_touch(
                    .a          = a
                    .b          = b
                    .c          = near
                    .d          = farther
                    .tolerance  = 0.000001
                    .resolution = _float_resolution#(Float64)().value
                )!
            ]
        )!
    ]
}

test geometry_orientation_float32_uncertainty := (.system: System) -> !() {
    a: _RegionPoint#(Float32) = (0.0, 0.0)
    b: _RegionPoint#(Float32) = (1.0, 1.0)
    p: _RegionPoint#(Float32) = (2.0, 2.0000002)
    [
        testing.expect_error(
            .expected_reason = ..numerical_ambiguity
            .actual_result   = _region_orientation(
                .a = a, .b = b, .p = p, .resolution = _float_resolution#(Float32)().value
            )
        )!
    ]
}

test geometry_contact_rejects_uncertain_distance := (.system: System) -> !() {
    a: _RegionPoint#(Float64) = (0.0, 0.0)
    b: _RegionPoint#(Float64) = (2.0, 2.0)
    p: _RegionPoint#(Float64) = (1.0, 1.0000000000000002)
    [
        testing.expect_error(
            .expected_reason = ..numerical_ambiguity
            .actual_result   = _region_near_segment(
                .a          = a
                .b          = b
                .p          = p
                .tolerance  = 0.000000000000000001
                .resolution = _float_resolution#(Float64)().value
            )
        )!
    ]
}

test geometry_contact_rejects_underflowed_budget := (.system: System) -> !() {
    a: _RegionPoint#(Float64) = (0.0, 0.0)
    b: _RegionPoint#(Float64) = (1.0e-310, 0.0)
    p: _RegionPoint#(Float64) = (0.5e-310, 1.0e-320)
    tolerance: Float64 = 1.0e-320
    [
        testing.expect_error(
            .expected_reason = ..numerical_ambiguity
            .actual_result   = _region_near_segment(
                .a          = a
                .b          = b
                .p          = p
                .tolerance  = tolerance
                .resolution = _float_resolution#(Float64)().value
            )
        )!
    ]
}
