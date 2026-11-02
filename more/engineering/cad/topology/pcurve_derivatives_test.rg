_check_pcurve_derivatives := #(.Scalar: Type: Float) () -> !Void {

    line: PCurve#(Scalar) = ..line(.start = (.u = 1.0, .v = -2.0), .end = (.u = 4.0, .v = 2.0))
    ellipse: PCurve#(Scalar) = ..ellipse(
        .center = (.u = 1.0, .v = -2.0)
        .cosine = (.u = 2.0, .v = 0.5)
        .sine   = (.u = 0.25, .v = 1.5)
        .start  = 5.5
        .end    = 8.0
    )
    harmonic: PCurve#(Scalar) = ..harmonic(
        .origin = (.u = 1.0, .v = -2.0)
        .linear = (.u = 0.5, .v = 0.25)
        .cosine = (.u = 2.0, .v = 0.5)
        .sine   = (.u = 0.25, .v = 1.5)
        .start  = 8.0
        .end    = 5.5
    )
    curves: [3]PCurve#(Scalar) = (line, ellipse, harmonic)
    parameters: [3]Scalar = (0.2, 0.5, 0.8)
    h: Scalar = 0.001
    for curve in curves {
        for parameter in parameters {
            a ::= pcurve_point(.curve = curve, .parameter = parameter - h)!
            b ::= pcurve_point(.curve = curve, .parameter = parameter + h)!
            actual ::= pcurve_derivative(.curve = curve, .parameter = parameter)!
            du ::= [b.u - a.u] / [2.0 * h]
            dv ::= [b.v - a.v] / [2.0 * h]
            delta_u ::= actual.u - du
            delta_v ::= actual.v - dv
            [
                testing.expect(
                    [
                        hypot(.left = delta_u, .right = delta_v).result
                        < 0.003 * [1.0 + hypot(.left = du, .right = dv).result]
                    ]
                )!
            ]
        }
        [pcurve_derivative(.curve = curve, .parameter = 0.0)!]
        [pcurve_derivative(.curve = curve, .parameter = 1.0)!]
    }
    actual ::= pcurve_derivative(.curve = line, .parameter = 0.0)!
    testing.expect(actual.u == 3.0 and actual.v == 4.0)!
    stationary: PCurve#(Scalar) = ..ellipse(
        .center = (.u = 1.0, .v = -2.0)
        .cosine = (.u = 2.0, .v = 0.5)
        .sine   = (.u = 0.25, .v = 1.5)
        .start  = 0.7
        .end    = 0.7
    )
    zero ::= pcurve_derivative(.curve = stationary, .parameter = 0.5)!
    testing.expect(zero.u == 0.0 and zero.v == 0.0)!
    result = ..ok Void()
}

test model_pcurve_derivatives_float32 := (.system: System) -> !() {
    [_check_pcurve_derivatives#(Float32)()!]
}

test model_pcurve_derivatives_float64 := (.system: System) -> !() {
    [_check_pcurve_derivatives#(Float64)()!]
}

test model_pcurve_derivatives_reject_nonfinite_coefficients_parameters_and_results := (
    .system : System
) -> !() {
    nan ::= sqrt#(Float64)(.value = -1.0).result
    bad_origin: PCurve#(Float64) = ..ellipse(
        .center = (.u = nan, .v = 0.0)
        .cosine = (.u = 2.0, .v = 0.0)
        .sine   = (.u = 0.0, .v = 1.0)
        .start  = 0.0
        .end    = 1.0
    )
    [
        testing.expect_error(
            .actual_result   = pcurve_point(.curve = bad_origin, .parameter = 0.0)
            .expected_reason = ..invalid_coordinate
        )!
    ]
    [
        testing.expect_error(
            .actual_result   = pcurve_derivative(.curve = bad_origin, .parameter = 0.0)
            .expected_reason = ..invalid_coordinate
        )!
    ]
    huge: PCurve#(Float64) = ..line(
        .start = (.u = -1.0e308, .v = 0.0)
        .end   = (.u = 1.0e308, .v = 0.0)
    )
    [
        testing.expect_error(
            .actual_result   = pcurve_derivative(.curve = huge, .parameter = 0.5)
            .expected_reason = ..numeric_range
        )!
    ]
    [
        testing.expect_error(
            .actual_result   = pcurve_derivative(.curve = huge, .parameter = -0.1)
            .expected_reason = ..out_of_bounds
        )!
    ]
    [
        testing.expect_error(
            .actual_result   = pcurve_derivative(.curve = huge, .parameter = nan)
            .expected_reason = ..out_of_bounds
        )!
    ]
}
