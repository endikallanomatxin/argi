test geometry_float32 := (.system: System) -> !() {
    a: Point#(Float32) = (1.0, 2.0, 3.0)
    b: Point#(Float32) = (4.0, 6.0, 3.0)
    delta ::= between#(Float32)(.from = a, .to = b).result
    testing.expect(delta.x == 3.0 and delta.y == 4.0 and delta.z == 0.0)!
    testing.expect(dot#(Float32)(.left = delta, .right = delta).value == 25.0)!
    x: Displacement#(Float32) = (1.0, 0.0, 0.0)
    y: Displacement#(Float32) = (0.0, 1.0, 0.0)
    normal ::= cross#(Float32)(.left = x, .right = y).result
    testing.expect(normal.x == 0.0 and normal.y == 0.0 and normal.z == 1.0)!
}

test geometry_float64 := (.system: System) -> !() {
    a: Point#(Float64) = (1.0, 2.0, 3.0)
    b: Point#(Float64) = (4.0, 6.0, 3.0)
    delta ::= between#(Float64)(.from = a, .to = b).result
    testing.expect(delta.x == 3.0 and delta.y == 4.0 and delta.z == 0.0)!
    testing.expect(dot#(Float64)(.left = delta, .right = delta).value == 25.0)!
    x: Displacement#(Float64) = (1.0, 0.0, 0.0)
    y: Displacement#(Float64) = (0.0, 1.0, 0.0)
    normal ::= cross#(Float64)(.left = x, .right = y).result
    testing.expect(normal.x == 0.0 and normal.y == 0.0 and normal.z == 1.0)!
}

test geometry_contextual_coordinates := () -> !() {
    point: Point#(Float64) = (1.0, 2.0, 3.0)
    other: Point#(Float64) = (4.0, 6.0, 8.0)
    displacement ::= between(point, other).result
    testing.expect(displacement.x == 3.0 and displacement.y == 4.0 and displacement.z == 5.0)!
    points: [2]Point#(Float32) = (
        (1.0, 2.0, 3.0),
        (4.0, 5.0, 6.0)
    )
    testing.expect(points[1].z == 6.0)!
}
