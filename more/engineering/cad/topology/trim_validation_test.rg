test model_trim_distinguishes_unsupported_parameterization := (.system: System) -> !() {
    basis ::= [
        g.frame#(Float64)(.origin = (0.0, 0.0, 0.0), .axis = (0.0, 0.0, 1.0))!
    ]
    plane: g.Surface#(Float64) = ..plane(
        .value = (.origin = basis.origin, .normal = basis.z)
    )
    circle: Curve#(Float64) = ..circle(.value = (.frame = basis, .radius = 2.0))
    -- A full-period shift describes the same geometric circle, but is outside
    -- the current certificate's canonical parameterization contract.
    shifted: PCurve#(Float64) = ..ellipse(
        .center = (.u = 0.0, .v = 0.0)
        .cosine = (.u = 2.0, .v = 0.0)
        .sine   = (.u = 0.0, .v = 2.0)
        .start  = 6.283185307179586
        .end    = 12.566370614359172
    )
    [
        testing.expect_error(
            .actual_result = _certify_circular_trim(
                .surface   = plane
                .curve     = circle
                .interval  = (.start = 0.0, .end = 1.0)
                .pcurve    = shifted
                .tolerance = 0.000001
            )
            .expected_reason = ..unsupported_parameterization
        )!
    ]
}
