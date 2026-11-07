_DifferentialTopologyErrors := choice_union#(
    .a : BuildErrors,
    .b : (
        ..test_failed,
        ..invalid_parameter,
        ..unsupported_boundary,
        ..unsupported_parameterization
    )
)

_expect_curve_derivative := #(.Scalar: Type: Float) (
    .actual    : g.Displacement#(Scalar),
    .expected  : g.Displacement#(Scalar),
    .tolerance : Scalar                   = 0.002
) -> !Void {

    delta: g.Displacement#(Scalar) = (
        .x = actual.x - expected.x
        .y = [actual.y - expected.y]
        .z = [actual.z - expected.z]
    )
    [
        testing.expect([g.norm(delta).value < tolerance * [1.0 + g.norm(expected).value]])!
    ]
    result = ..ok Void()
}

_check_normalized_curve_derivatives := #(.Scalar: Type: Float) (.basis: g.Frame#(Scalar)) -> !Void {

    segment: Curve#(Scalar) = ..segment(
        .start = basis.origin
        .end   = (4.0, 0.0, 4.0)
    )
    circle: Curve#(Scalar) = ..circle(.value = (.frame = basis, .radius = 2.5))
    ellipse: Curve#(Scalar) = ..ellipse(
        .value = (
            .center = basis.origin
            .cosine = (2.0, 0.5, 1.0)
            .sine   = (0.5, 1.5, -0.25)
        )
    )
    curves: [3]Curve#(Scalar) = (segment, circle, ellipse)
    parameters: [2]Scalar = (0.2, 0.7)
    h: Scalar = 0.001
    for curve in curves {
        for parameter in parameters {
            a ::= curve_point(.curve = curve, .parameter = parameter - h)!
            b ::= curve_point(.curve = curve, .parameter = parameter + h)!
            secant: g.Displacement#(Scalar) = (
                .x = [b.x - a.x] / [2.0 * h]
                .y = [[b.y - a.y] / [2.0 * h]]
                .z = [[b.z - a.z] / [2.0 * h]]
            )
            [
                _expect_curve_derivative(
                    .actual    = [curve_derivative(.curve = curve, .parameter = parameter)!]
                    .expected  = secant
                    .tolerance = 0.002
                )!
            ]
        }
        [curve_derivative(.curve = curve, .parameter = 0.0)!]
        [curve_derivative(.curve = curve, .parameter = 1.0)!]
    }
    speed ::= g.norm([curve_derivative(.curve = circle, .parameter = 0.0)!]).value
    testing.expect(speed > 15.7079 and speed < 15.7081)!
    result = ..ok Void()
}

test model_normalized_curve_derivatives_float32 := (.system: System) -> !() {
    basis ::= [
        g.frame#(Float32)(.origin = (3.0, -2.0, 1.0), .axis = (1.0, 2.0, 3.0))!
    ]
    [_check_normalized_curve_derivatives(.basis = basis)!]
}

test model_normalized_curve_derivatives_float64 := (.system: System) -> !() {
    basis ::= [
        g.frame#(Float64)(.origin = (3.0, -2.0, 1.0), .axis = (1.0, 2.0, 3.0))!
    ]
    [_check_normalized_curve_derivatives(.basis = basis)!]
}

_check_interval_derivatives := #(.Scalar: Type: Float) (
    .allocator : Virtual#(Allocator)
) -> !Void {

    original ::= _partitioned_oblique_cylinder#(.Scalar: Scalar)(.allocator = allocator)!
    inverted ::= reverse_orientation(&original, .allocator = allocator)!
    h: Scalar = 0.001
    i :: UIntNative = 0
    while i < entity_counts(&original).halfedges {
        id ::= i | convert#(.to: HalfEdgeId)(_)
        parameters: [3]Scalar = (0.0, 0.4, 1.0)
        for parameter in parameters {
            derivative ::= [
                halfedge_derivative(&original, .halfedge = id, .parameter = parameter)!
            ]
            back ::= [
                halfedge_derivative(&inverted, .halfedge = id, .parameter = 1.0 - parameter)!
            ]
            negative: g.Displacement#(Scalar) = (
                .x = 0.0 - derivative.x
                .y = [0.0 - derivative.y]
                .z = [0.0 - derivative.z]
            )
            [
                _expect_curve_derivative(
                    .actual = back, .expected = negative, .tolerance = 0.00001
                )!
            ]
            info ::= halfedge_info(&original, .halfedge = id)!
            interval ::= edge_interval(&original, .edge = info.edge)!
            match [edge_curve(&original, .edge = info.edge)!] {
                ..circle c {
                    expected ::= [
                        c.value.radius
                        * 6.283185307179586
                        * [interval.end - interval.start]
                    ]
                    [
                        testing.expect(
                            [
                                g.norm(derivative).value > expected * 0.9999
                                and g.norm(derivative).value < expected * 1.0001
                            ]
                        )!
                    ]
                }
                ..segment _ {}
                ..ellipse _ {}
            }
            if parameter > h and parameter < 1.0 - h {
                a ::= halfedge_point(&original, .halfedge = id, .parameter = parameter - h)!
                b ::= halfedge_point(&original, .halfedge = id, .parameter = parameter + h)!
                secant: g.Displacement#(Scalar) = (
                    .x = [b.x - a.x] / [2.0 * h]
                    .y = [[b.y - a.y] / [2.0 * h]]
                    .z = [[b.z - a.z] / [2.0 * h]]
                )
                [_expect_curve_derivative(.actual = derivative, .expected = secant)!]
            }
        }
        i = i + 1
    }
    result = ..ok Void()
}

test model_interval_derivatives_period_crossing_and_orientation_float32 := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    [_check_interval_derivatives#(.Scalar: Float32)(.allocator = allocator)!]
}

test model_interval_derivatives_period_crossing_and_orientation_float64 := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    [_check_interval_derivatives#(.Scalar: Float64)(.allocator = allocator)!]
}

test model_curve_derivative_rejects_nonfinite_results := (.system: System) -> !() {
    segment: Curve#(Float64) = ..segment(
        .start = (-1.0e308, 0.0, 0.0)
        .end   = (1.0e308, 0.0, 0.0)
    )
    [
        testing.expect_error(
            .actual_result   = curve_derivative(.curve = segment, .parameter = 0.5)
            .expected_reason = ..numeric_range
        )!
    ]
    basis ::= [
        g.frame#(Float64)(.origin = (0.0, 0.0, 0.0), .axis = (0.0, 0.0, 1.0))!
    ]
    huge: Curve#(Float64) = ..circle(.value = (.frame = basis, .radius = 1.0e308))
    [
        testing.expect_error(
            .actual_result   = curve_derivative(.curve = huge, .parameter = 0.0)
            .expected_reason = ..numeric_range
        )!
    ]
    nan ::= sqrt#(Float64)(.value = -1.0).result
    [
        testing.expect_error(
            .actual_result   = curve_derivative(.curve = segment, .parameter = -0.1)
            .expected_reason = ..out_of_bounds
        )!
    ]
    [
        testing.expect_error(
            .actual_result   = curve_derivative(.curve = segment, .parameter = nan)
            .expected_reason = ..out_of_bounds
        )!
    ]
}
