_DifferentialTestErrors := choice_union#(.a: GeometryErrors, .b: (..test_failed))

_expect_derivative_near := #(.Scalar: Type: Float) (
    .actual: Displacement#(Scalar), .expected: Displacement#(Scalar), .tolerance: Scalar
) -> !Void {

    difference: Displacement#(Scalar) = (
        .x = actual.x - expected.x
        .y = actual.y - expected.y
        .z = [actual.z - expected.z]
    )
    testing.expect(norm(difference).value <= tolerance * [1.0 + norm(expected).value])!
    result = ..ok Void()
}

_check_surface_derivatives := #(.Scalar: Type: Float) () -> !Void {

    basis ::= [
        frame#(Scalar)(.origin = (3.0, -2.0, 1.0), .axis = (1.0, 2.0, 3.0))!
    ]
    plane: Surface#(Scalar) = ..plane(.value = (.origin = basis.origin, .normal = basis.z))
    cylinder: Surface#(Scalar) = ..cylinder(.frame = basis, .radius = 2.5)
    sphere: Surface#(Scalar) = ..sphere(.frame = basis, .radius = 2.5)
    torus: Surface#(Scalar) = ..torus(.frame = basis, .major_radius = 4.0, .minor_radius = 1.5)
    supports: [4]Surface#(Scalar) = (plane, cylinder, sphere, torus)
    parameters: [3]Scalar = (-0.7, 0.3, 7.0)
    h: Scalar = 0.002
    for support in supports {
        for u in parameters {
            v: Scalar = 0.4
            actual ::= surface_derivatives(.surface = support, .u = u, .v = v)!
            testing.expect(actual.singular == false)!
            left ::= surface_point(.surface = support, .u = u - h, .v = v)!
            right ::= surface_point(.surface = support, .u = u + h, .v = v)!
            down ::= surface_point(.surface = support, .u = u, .v = v - h)!
            up ::= surface_point(.surface = support, .u = u, .v = v + h)!
            secant_u: Displacement#(Scalar) = (
                .x = [right.x - left.x] / [2.0 * h]
                .y = [[right.y - left.y] / [2.0 * h]]
                .z = [[right.z - left.z] / [2.0 * h]]
            )
            secant_v: Displacement#(Scalar) = (
                .x = [up.x - down.x] / [2.0 * h]
                .y = [[up.y - down.y] / [2.0 * h]]
                .z = [[up.z - down.z] / [2.0 * h]]
            )
            [
                _expect_derivative_near(
                    .actual = actual.du, .expected = secant_u, .tolerance = 0.001
                )!
            ]
            [
                _expect_derivative_near(
                    .actual = actual.dv, .expected = secant_v, .tolerance = 0.001
                )!
            ]
            normal ::= surface_normal(.surface = support, .u = u, .v = v)!
            oriented ::= cross(.left = actual.du, .right = actual.dv).result
            [
                testing.expect(
                    [
                        dot(.left = normal, .right = oriented).value / norm(oriented).value
                        > 0.9999
                    ]
                )!
            ]
            [
                testing.expect(
                    [_absolute(dot(.left = normal, .right = actual.du).value).result < 0.0001]
                )!
            ]
            [
                testing.expect(
                    [_absolute(dot(.left = normal, .right = actual.dv).value).result < 0.0001]
                )!
            ]
        }
    }
    period: Scalar = 6.283185307179586
    periodic_u: Scalar = -0.7
    periodic_v: Scalar = 0.4
    a ::= surface_derivatives(.surface = torus, .u = periodic_u, .v = periodic_v)!
    b ::= [
        surface_derivatives(
            .surface = torus, .u = periodic_u + period, .v = periodic_v - period
        )!
    ]
    [_expect_derivative_near(.actual = a.du, .expected = b.du, .tolerance = 0.00001)!]
    [_expect_derivative_near(.actual = a.dv, .expected = b.dv, .tolerance = 0.00001)!]
    poles: [2]Scalar = (-1.5707963267948966, 1.5707963267948966)
    for v in poles {
        at ::= surface_derivatives(.surface = sphere, .u = 0.7, .v = v)!
        testing.expect(at.singular and at.du.x == 0.0 and at.du.y == 0.0 and at.du.z == 0.0)!
        testing.expect(_absolute(norm(at.dv).value - 2.5).result < 0.00001)!
        normal ::= surface_normal(.surface = sphere, .u = 0.7, .v = v)!
        testing.expect(_absolute(dot(.left = normal, .right = at.dv).value).result < 0.00001)!
    }
    near ::= surface_derivatives(.surface = sphere, .u = 0.7, .v = 1.5707)!
    testing.expect(near.singular == false and norm(near.du).value > 0.0)!
    result = ..ok Void()
}

test geometry_surface_derivatives_float32 := (.system: System) -> !() {
    [_check_surface_derivatives#(Float32)()!]
}

test geometry_surface_derivatives_float64 := (.system: System) -> !() {
    [_check_surface_derivatives#(Float64)()!]
}

test geometry_surface_derivatives_validate_domain_and_numeric_range := (.system: System) -> !() {
    basis ::= [
        frame#(Float64)(.origin = (1.0e200, 0.0, 0.0), .axis = (0.0, 0.0, 1.0))!
    ]
    sphere: Surface#(Float64) = ..sphere(.frame = basis, .radius = 2.0)
    a ::= surface_derivatives(.surface = sphere, .u = 0.0, .v = 0.0)!
    testing.expect(norm(a.du).value == 2.0 and norm(a.dv).value == 2.0)!
    [
        testing.expect_error(
            .actual_result   = surface_derivatives(.surface = sphere, .u = 0.0, .v = 2.0)
            .expected_reason = ..out_of_bounds
        )!
    ]
    nan ::= sqrt#(Float64)(.value = -1.0).result
    [
        testing.expect_error(
            .actual_result   = surface_derivatives(.surface = sphere, .u = nan, .v = 0.0)
            .expected_reason = ..invalid_coordinate
        )!
    ]
    invalid: Surface#(Float64) = ..cylinder(.frame = basis, .radius = 0.0)
    [
        testing.expect_error(
            .actual_result   = surface_derivatives(.surface = invalid, .u = 0.0, .v = 0.0)
            .expected_reason = ..invalid_surface
        )!
    ]
    huge: Surface#(Float64) = ..torus(
        .frame        = basis
        .major_radius = 1.0e308
        .minor_radius = 9.0e307
    )
    [
        testing.expect_error(
            .actual_result   = surface_derivatives(.surface = huge, .u = 0.0, .v = 0.0)
            .expected_reason = ..numeric_range
        )!
    ]
}
