_check_angular_derivatives := #(.Scalar: Type: Float) () -> !Void {

    basis ::= [
        frame#(Scalar)(.origin = (3.0, -2.0, 1.0), .axis = (1.0, 2.0, 3.0))!
    ]
    circle: Circle#(Scalar) = (.frame = basis, .radius = 2.5)
    ellipse: Ellipse#(Scalar) = (
        .center = basis.origin
        .cosine = (2.0, 0.5, 1.0)
        .sine   = (0.5, 1.5, -0.25)
    )
    angles: [4]Scalar = (-1.0, 0.0, 0.7, 7.0)
    h: Scalar = 0.002
    for angle in angles {
        a ::= circle_point(.circle = circle, .angle = angle - h)!
        b ::= circle_point(.circle = circle, .angle = angle + h)!
        secant: Displacement#(Scalar) = (
            .x = [b.x - a.x] / [2.0 * h]
            .y = [[b.y - a.y] / [2.0 * h]]
            .z = [[b.z - a.z] / [2.0 * h]]
        )
        derivative ::= circle_derivative(.circle = circle, .angle = angle)!
        [_expect_derivative_near(.actual = derivative, .expected = secant, .tolerance = 0.001)!]
        testing.expect(_absolute(norm(derivative).value - circle.radius).result < 0.00001)!
        p ::= ellipse_point(.ellipse = ellipse, .angle = angle - h)!
        q ::= ellipse_point(.ellipse = ellipse, .angle = angle + h)!
        ellipse_secant: Displacement#(Scalar) = (
            .x = [q.x - p.x] / [2.0 * h]
            .y = [[q.y - p.y] / [2.0 * h]]
            .z = [[q.z - p.z] / [2.0 * h]]
        )
        [
            _expect_derivative_near(
                .actual    = [ellipse_derivative(.ellipse = ellipse, .angle = angle)!]
                .expected  = ellipse_secant
                .tolerance = 0.001
            )!
        ]
    }
    first ::= ellipse_derivative(.ellipse = ellipse, .angle = 0.0)!
    [_expect_derivative_near(.actual = first, .expected = ellipse.sine, .tolerance = 0.000001)!]
    result = ..ok Void()
}

test geometry_angular_derivatives_float32 := (.system: System) -> !() {
    [_check_angular_derivatives#(Float32)()!]
}

test geometry_angular_derivatives_float64 := (.system: System) -> !() {
    [_check_angular_derivatives#(Float64)()!]
}

test geometry_ellipse_validation_and_derivatives_avoid_squared_scale := (.system: System) -> !() {
    scales: [2]Float64 = (1.0e-200, 1.0e200)
    for scale in scales {
        ellipse: Ellipse#(Float64) = (
            .center = (1.0e200, 0.0, 0.0)
            .cosine = (scale, 0.0, 0.0)
            .sine   = (0.0, scale, 0.0)
        )
        [validate_ellipse(ellipse)!]
        point ::= ellipse_point(.ellipse = ellipse, .angle = 0.0)!
        testing.expect(finite_point(point).ok)!
        derivative ::= ellipse_derivative(.ellipse = ellipse, .angle = 0.0)!
        testing.expect(derivative.x == 0.0 and derivative.y == scale and derivative.z == 0.0)!
    }
    basis ::= [
        frame#(Float64)(.origin = (0.0, 0.0, 0.0), .axis = (0.0, 0.0, 1.0))!
    ]
    invalid: Circle#(Float64) = (.frame = basis, .radius = 0.0)
    [
        testing.expect_error(
            .actual_result   = circle_derivative(.circle = invalid, .angle = 0.0)
            .expected_reason = ..invalid_surface
        )!
    ]
    ellipse: Ellipse#(Float64) = (.center = basis.origin, .cosine = basis.x, .sine = basis.x)
    [
        testing.expect_error(
            .actual_result   = ellipse_derivative(.ellipse = ellipse, .angle = 0.0)
            .expected_reason = ..invalid_surface
        )!
    ]
    nan ::= sqrt#(Float64)(.value = -1.0).result
    valid: Circle#(Float64) = (.frame = basis, .radius = 1.0)
    [
        testing.expect_error(
            .actual_result   = circle_derivative(.circle = valid, .angle = nan)
            .expected_reason = ..invalid_coordinate
        )!
    ]
}
