test geometry_ellipse_conjugate_axes := (.system: System) -> !() {
    ellipse: Ellipse#(Float64) = (
        .center = (1.0, -2.0, 3.0)
        .cosine = (2.0, 0.0, 0.5)
        .sine   = (0.25, 1.0, 0.0)
    )
    a ::= ellipse_point(.ellipse = ellipse, .angle = 0.0)!
    testing.expect(a.x == 3.0 and a.y == -2.0 and a.z == 3.5)!
    b ::= ellipse_point(.ellipse = ellipse, .angle = 1.5707963267948966)!
    testing.expect(_absolute(b.x - 1.25).result < 0.000000000001)!
    testing.expect(_absolute(b.y + 1.0).result < 0.000000000001)!
    invalid: Ellipse#(Float64) = (
        .center = ellipse.center
        .cosine = ellipse.cosine
        .sine   = ellipse.cosine
    )
    [
        testing.expect_error(
            .actual_result   = ellipse_point(.ellipse = invalid, .angle = 0.0)
            .expected_reason = ..invalid_surface
        )!
    ]
    nan ::= sqrt#(Float64)(.value = -1.0).result
    [
        testing.expect_error(
            .actual_result   = ellipse_point(.ellipse = ellipse, .angle = nan)
            .expected_reason = ..invalid_coordinate
        )!
    ]
}
