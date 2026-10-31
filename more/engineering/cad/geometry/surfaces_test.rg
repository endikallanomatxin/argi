_surface_frame := () -> (.value: Frame#(Float64)) {
    value = (
        .origin = (0.0, 0.0, 0.0)
        .x      = (1.0, 0.0, 0.0)
        .y      = (0.0, 1.0, 0.0)
        .z      = (0.0, 0.0, 1.0)
    )
}

test geometry_surface_frames := (.system: System) -> !() {
    basis ::= [
        frame#(Float64)(.origin = (3.0, -2.0, 1.0), .axis = (2.0, 3.0, -4.0))!
    ]
    [validate_frame(basis)!]
    testing.expect(_absolute(norm(basis.x).value - 1.0).result < 0.00000000000001)!
    [
        testing.expect(
            [_absolute(dot(.left = basis.x, .right = basis.z).value).result < 0.00000000000001]
        )!
    ]
    small ::= [
        frame#(Float32)(.origin = (0.0, 0.0, 0.0), .axis = (1.0e-30, -2.0e-30, 3.0e-30))!
    ]
    [validate_frame(small)!]
    [
        testing.expect_error(
            .expected_reason = ..degenerate_face
            .actual_result   = frame#(Float64)(.origin = basis.origin, .axis = (0.0, 0.0, 0.0))
        )!
    ]
    basis = _surface_frame().value
    basis.y.x = 0.001
    [
        testing.expect_error(
            .expected_reason = ..degenerate_face, .actual_result = validate_frame(basis)
        )!
    ]
    basis = _surface_frame().value
    basis.z.z = -1.0
    [
        testing.expect_error(
            .expected_reason = ..degenerate_face, .actual_result = validate_frame(basis)
        )!
    ]
}

test geometry_surface_charts := (.system: System) -> !() {
    basis ::= _surface_frame().value
    sphere: Surface#(Float64) = ..sphere(.frame = basis, .radius = 2.0)
    equator ::= surface_point(.surface = sphere, .u = 0.0, .v = 0.0)!
    pole ::= surface_point(.surface = sphere, .u = 1.0, .v = 1.5707963267948966)!
    testing.expect(equator.x == 2.0 and equator.y == 0.0 and equator.z == 0.0)!
    testing.expect(_absolute(pole.x).result < 0.000000000001 and pole.z == 2.0)!
    torus: Surface#(Float64) = ..torus(
        .frame        = basis
        .major_radius = 3.0
        .minor_radius = 1.0
    )
    outer ::= surface_point(.surface = torus, .u = 0.0, .v = 0.0)!
    inner ::= surface_point(.surface = torus, .u = 0.0, .v = 3.141592653589793)!
    testing.expect(outer.x == 4.0 and inner.x == 2.0)!
    cylinder: Surface#(Float64) = ..cylinder(.frame = basis, .radius = 2.0)
    top ::= surface_point(.surface = cylinder, .u = 0.0, .v = 3.0)!
    testing.expect(top.x == 2.0 and top.z == 3.0)!
    plane: Surface#(Float64) = ..plane(.value = (.origin = basis.origin, .normal = basis.z))
    [
        testing.expect(
            [surface_periodicity(plane).u == false and surface_periodicity(plane).v == false]
        )!
    ]
    testing.expect(surface_periodicity(sphere).u and surface_periodicity(sphere).v == false)!
    [
        testing.expect(
            surface_periodicity(cylinder).u and surface_periodicity(cylinder).v == false
        )!
    ]
    testing.expect(surface_periodicity(torus).u and surface_periodicity(torus).v)!
}

test geometry_surface_invalid_evaluation := (.system: System) -> !() {
    basis ::= _surface_frame().value
    nan ::= sqrt#(Float64)(.value = -1.0).result
    support :: Surface#(Float64) = ..sphere(.frame = basis, .radius = 2.0)
    [
        testing.expect_error(
            .expected_reason = ..invalid_coordinate
            .actual_result   = surface_point(.surface = support, .u = nan, .v = 0.0)
        )!
    ]
    support = ..sphere(.frame = basis, .radius = nan)
    [
        testing.expect_error(
            .expected_reason = ..invalid_surface
            .actual_result   = surface_point(.surface = support, .u = 0.0, .v = 0.0)
        )!
    ]
    support = ..torus(.frame = basis, .major_radius = 1.0, .minor_radius = 1.0)
    [
        testing.expect_error(
            .expected_reason = ..invalid_surface, .actual_result = validate_surface(support)
        )!
    ]
    basis.origin.x = 1.0e308
    support = ..sphere(.frame = basis, .radius = 1.0e308)
    [
        testing.expect_error(
            .expected_reason = ..numeric_range
            .actual_result   = surface_point(.surface = support, .u = 0.0, .v = 0.0)
        )!
    ]
}

test geometry_circle_evaluation := (.system: System) -> !() {
    basis ::= _surface_frame().value
    circle :: Circle#(Float64) = (.frame = basis, .radius = 2.0)
    a ::= circle_point(.circle = circle, .angle = 0.0)!
    b ::= circle_point(.circle = circle, .angle = 6.283185307179586)!
    testing.expect(norm(between(.from = a, .to = b).result).value < 0.000000000001)!
    circle.radius = -1.0
    [
        testing.expect_error(
            .expected_reason = ..invalid_surface
            .actual_result   = circle_point(.circle = circle, .angle = 0.0)
        )!
    ]
}
