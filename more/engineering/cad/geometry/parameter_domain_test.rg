_ParameterDomainTestErrors := choice_union#(.a: GeometryErrors, .b: (..test_failed))

_check_parameter_domains := #(.Scalar: Type: Float) (.basis: Frame#(Scalar)) -> !Void {

    plane: Surface#(Scalar) = ..plane(.value = (.origin = basis.origin, .normal = basis.z))
    cylinder: Surface#(Scalar) = ..cylinder(.frame = basis, .radius = 2.0)
    sphere: Surface#(Scalar) = ..sphere(.frame = basis, .radius = 2.0)
    torus: Surface#(Scalar) = ..torus(.frame = basis, .major_radius = 3.0, .minor_radius = 1.0)
    match surface_parameter_domain#(Scalar)(plane).domain.u {
        ..unbounded {}
        ..bounded _ { [testing.fail()!] }
        ..periodic _ { [testing.fail()!] }
    }
    match surface_parameter_domain#(Scalar)(cylinder).domain.v {
        ..unbounded {}
        ..bounded _ {
            testing.fail()!
        }
        ..periodic _ {
            testing.fail()!
        }
    }
    match surface_parameter_domain#(Scalar)(sphere).domain.v {
        ..bounded latitude {
            [
                testing.expect(
                    [
                        latitude.lower == -1.5707963267948966
                        and latitude.upper == 1.5707963267948966
                    ]
                )!
            ]
            testing.expect(latitude.lower_singular and latitude.upper_singular)!
        }
        ..unbounded { [testing.fail()!] }
        ..periodic _ { [testing.fail()!] }
    }
    tau :: Scalar = 0.0
    match surface_parameter_domain#(Scalar)(torus).domain.u {
        ..periodic axis {
            tau = axis.period
            testing.expect(axis.origin == 0.0)!
        }
        ..unbounded { [testing.fail()!] }
        ..bounded _ { [testing.fail()!] }
    }
    match surface_parameter_domain#(Scalar)(torus).domain.v {
        ..periodic axis {
            testing.expect(axis.period == tau and axis.origin == 0.0)!
        }
        ..unbounded { [testing.fail()!] }
        ..bounded _ { [testing.fail()!] }
    }
    testing.expect(tau > 6.28 and tau < 6.29)!
    [
        testing.expect(
            [
                surface_periodicity#(Scalar)(plane).u == false
                and surface_periodicity#(Scalar)(cylinder).u
            ]
        )!
    ]
    [
        testing.expect(
            [
                surface_periodicity#(Scalar)(sphere).v == false
                and surface_periodicity#(Scalar)(torus).v
            ]
        )!
    ]
    [
        testing.expect(
            [
                validate_surface_parameters#(Scalar)(
                    .surface = sphere, .u = 11.0, .v = 1.5707963267948966
                )!
            ]
        )!
    ]
    [
        testing.expect(
            [
                validate_surface_parameters#(Scalar)(
                    .surface = sphere, .u = -9.0, .v = -1.5707963267948966
                )!
            ]
        )!
    ]
    [
        testing.expect(
            [
                [validate_surface_parameters#(Scalar)(.surface = sphere, .u = 11.0, .v = 1.5707)!]
                == false
            ]
        )!
    ]
    [
        testing.expect(
            [
                [
                    validate_surface_parameters#(Scalar)(
                        .surface = cylinder, .u = -9.0, .v = -100.0
                    )!
                ]
                == false
            ]
        )!
    ]
    [
        testing.expect(
            [
                [validate_surface_parameters#(Scalar)(.surface = torus, .u = -9.0, .v = 20.0)!]
                == false
            ]
        )!
    ]
    -- Unwrapped coordinates on both torus axes evaluate the same support.
    a ::= surface_point#(Scalar)(.surface = torus, .u = -0.25, .v = tau - 0.5)!
    b ::= surface_point#(Scalar)(.surface = torus, .u = tau - 0.25, .v = -0.5)!
    distance ::= norm#(Scalar)(.vector = between#(Scalar)(.from = a, .to = b).result).value
    testing.expect(distance < 0.00001)!
    north_a ::= surface_point#(Scalar)(.surface = sphere, .u = 0.0, .v = 1.5707963267948966)!
    north_b ::= surface_point#(Scalar)(.surface = sphere, .u = 3.0, .v = 1.5707963267948966)!
    [
        testing.expect(
            [
                norm#(Scalar)(
                    .vector = between#(Scalar)(.from = north_a, .to = north_b).result
                ).value
                < 0.00001
            ]
        )!
    ]
    result = ..ok Void()
}

test geometry_parameter_domains_float32 := (.system: System) -> !() {
    basis ::= [
        frame#(Float32)(.origin = (0.0, 0.0, 0.0), .axis = (0.0, 0.0, 1.0))!
    ]
    [_check_parameter_domains(.basis = basis)!]
}

test geometry_parameter_domains_float64 := (.system: System) -> !() {
    basis ::= [
        frame#(Float64)(.origin = (0.0, 0.0, 0.0), .axis = (0.0, 0.0, 1.0))!
    ]
    [_check_parameter_domains(.basis = basis)!]
}

test geometry_parameter_domain_rejects_invalid_coordinates := (.system: System) -> !() {
    basis ::= [
        frame#(Float64)(.origin = (0.0, 0.0, 0.0), .axis = (0.0, 0.0, 1.0))!
    ]
    sphere: Surface#(Float64) = ..sphere(.frame = basis, .radius = 2.0)
    [
        testing.expect_error(
            .actual_result   = surface_point(.surface = sphere, .u = 0.0, .v = 1.6)
            .expected_reason = ..out_of_bounds
        )!
    ]
    [
        testing.expect_error(
            .actual_result = validate_surface_parameters(
                .surface = sphere, .u = 0.0, .v = -1.6
            )
            .expected_reason = ..out_of_bounds
        )!
    ]
    nan ::= sqrt#(Float64)(.value = -1.0).result
    [
        testing.expect_error(
            .actual_result = validate_surface_parameters(
                .surface = sphere, .u = nan, .v = 0.0
            )
            .expected_reason = ..invalid_coordinate
        )!
    ]
    small_basis ::= [
        frame#(Float32)(.origin = (0.0, 0.0, 0.0), .axis = (0.0, 0.0, 1.0))!
    ]
    small: Surface#(Float32) = ..sphere(.frame = small_basis, .radius = 2.0)
    [
        testing.expect_error(
            .actual_result   = surface_point(.surface = small, .u = 0.0, .v = 1.6)
            .expected_reason = ..out_of_bounds
        )!
    ]
}
