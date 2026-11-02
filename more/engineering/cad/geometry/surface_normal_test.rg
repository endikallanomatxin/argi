_SurfaceNormalTestErrors := choice_union#(.a: GeometryErrors, .b: (..test_failed))

_check_surface_normals := #(.Scalar: Type: Float) (.basis: Frame#(Scalar)) -> !Void {

    plane: Surface#(Scalar) = ..plane(
        .value = (
            .origin = basis.origin
            .normal = (basis.z.x * 3.0, basis.z.y * 3.0, basis.z.z * 3.0)
        )
    )
    cylinder: Surface#(Scalar) = ..cylinder(.frame = basis, .radius = 2.0)
    sphere: Surface#(Scalar) = ..sphere(.frame = basis, .radius = 1000000.0)
    torus: Surface#(Scalar) = ..torus(.frame = basis, .major_radius = 3.0, .minor_radius = 1.0)
    supports: [4]Surface#(Scalar) = (plane, cylinder, sphere, torus)
    i :: UIntNative = 0
    while i < 4 {
        support ::= supports[i]
        n ::= surface_normal(.surface = support, .u = 0.3, .v = 0.4)!
        testing.expect(_absolute(norm(n).value - 1.0).result < 0.00001)!
        -- Centered secants independently check direction against the chart.
        h: Scalar = 0.01
        left ::= surface_point(.surface = support, .u = 0.3 - h, .v = 0.4)!
        right ::= surface_point(.surface = support, .u = 0.3 + h, .v = 0.4)!
        down ::= surface_point(.surface = support, .u = 0.3, .v = 0.4 - h)!
        up ::= surface_point(.surface = support, .u = 0.3, .v = 0.4 + h)!
        du ::= between(.from = left, .to = right).result
        dv ::= between(.from = down, .to = up).result
        expected ::= cross(.left = du, .right = dv).result
        cosine ::= dot(.left = n, .right = expected).value / norm(expected).value
        testing.expect(cosine > 0.999)!
        i = i + 1
    }
    north ::= surface_normal(.surface = sphere, .u = -9.0, .v = 1.5707963267948966)!
    other ::= surface_normal(.surface = sphere, .u = 5.0, .v = 1.5707963267948966)!
    south ::= surface_normal(.surface = sphere, .u = 17.0, .v = -1.5707963267948966)!
    testing.expect(north.x == other.x and north.y == other.y and north.z == other.z)!
    testing.expect(north.x == basis.z.x and north.y == basis.z.y and north.z == basis.z.z)!
    [
        testing.expect(
            [
                south.x == [0.0 - north.x]
                and south.y == [0.0 - north.y]
                and south.z == [0.0 - north.z]
            ]
        )!
    ]
    a ::= surface_normal(.surface = torus, .u = 0.0, .v = 0.0)!
    b ::= surface_normal(.surface = torus, .u = 6.283185307179586, .v = 6.283185307179586)!
    difference: Displacement#(Scalar) = (a.x - b.x, a.y - b.y, a.z - b.z)
    testing.expect(norm(difference).value < 0.00001)!
    result = ..ok Void()
}

test geometry_surface_normals_float32 := (.system: System) -> !() {
    basis ::= [
        frame#(Float32)(.origin = (0.0, 0.0, 0.0), .axis = (1.0, 2.0, 3.0))!
    ]
    [_check_surface_normals(.basis = basis)!]
}

test geometry_surface_normals_float64 := (.system: System) -> !() {
    basis ::= [
        frame#(Float64)(.origin = (0.0, 0.0, 0.0), .axis = (1.0, 2.0, 3.0))!
    ]
    [_check_surface_normals(.basis = basis)!]
}

test geometry_surface_normal_rejects_invalid_inputs := (.system: System) -> !() {
    basis ::= [
        frame#(Float64)(.origin = (0.0, 0.0, 0.0), .axis = (0.0, 0.0, 1.0))!
    ]
    sphere: Surface#(Float64) = ..sphere(.frame = basis, .radius = 2.0)
    invalid: Surface#(Float64) = ..cylinder(.frame = basis, .radius = 0.0)
    [
        testing.expect_error(
            .actual_result   = surface_normal(.surface = invalid, .u = 0.0, .v = 0.0)
            .expected_reason = ..invalid_surface
        )!
    ]
    [
        testing.expect_error(
            .actual_result   = surface_normal(.surface = sphere, .u = 0.0, .v = 1.6)
            .expected_reason = ..out_of_bounds
        )!
    ]
    nan ::= sqrt#(Float64)(.value = -1.0).result
    [
        testing.expect_error(
            .actual_result   = surface_normal(.surface = sphere, .u = nan, .v = 0.0)
            .expected_reason = ..invalid_coordinate
        )!
    ]
}

test geometry_surface_normal_independent_of_radius_and_translation := (.system: System) -> !() {
    basis ::= [
        frame#(Float64)(.origin = (1.0e100, -1.0e100, 1.0e100), .axis = (0.0, 0.0, 1.0))!
    ]
    tiny: Surface#(Float64) = ..sphere(.frame = basis, .radius = 1.0e-200)
    huge: Surface#(Float64) = ..sphere(.frame = basis, .radius = 1.0e200)
    a ::= surface_normal(.surface = tiny, .u = 0.7, .v = 0.2)!
    b ::= surface_normal(.surface = huge, .u = 0.7, .v = 0.2)!
    testing.expect(a.x == b.x and a.y == b.y and a.z == b.z)!
    testing.expect(norm(a).value > 0.999 and norm(a).value < 1.001)!
}
