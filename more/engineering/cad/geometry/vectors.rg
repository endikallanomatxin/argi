-- Geometry carries its precision at compile time
-- Topology never depends on it.
Point := #(.Scalar: Type: Float) (.x: Scalar, .y: Scalar, .z: Scalar)

Displacement := #(.Scalar: Type: Float) (.x: Scalar, .y: Scalar, .z: Scalar)

implement#(.Scalar: Type: Float) ImplicitlyCopyable#(Point#(Scalar)) ()

implement#(.Scalar: Type: Float) ImplicitlyCopyable#(Displacement#(Scalar)) ()

between := #(.Scalar: Type: Float) (.from: Point#(Scalar), .to: Point#(Scalar)) -> (
    .result : Displacement#(Scalar)
) {
    result = (to.x - from.x, to.y - from.y, to.z - from.z)
}

dot := #(.Scalar: Type: Float) (.left: Displacement#(Scalar), .right: Displacement#(Scalar)) -> (
    .value : Scalar
) {
    value = left.x * right.x + left.y * right.y + left.z * right.z
}

cross := #(.Scalar: Type: Float) (.left: Displacement#(Scalar), .right: Displacement#(Scalar)) -> (
    .result : Displacement#(Scalar)
) {
    result = (
        .x = left.y * right.z - left.z * right.y
        .y = left.z * right.x - left.x * right.z
        .z = left.x * right.y - left.y * right.x
    )
}

finite_point := #(.Scalar: Type: Float) (.point: Point#(Scalar)) -> (.ok: Bool) {
    ok = is_finite(point.x).ok and is_finite(point.y).ok and is_finite(point.z).ok
}

finite_displacement := #(.Scalar: Type: Float) (.vector: Displacement#(Scalar)) -> (.ok: Bool) {
    ok = is_finite(vector.x).ok and is_finite(vector.y).ok and is_finite(vector.z).ok
}

norm := #(.Scalar: Type: Float) (.vector: Displacement#(Scalar)) -> (.value: Scalar) {
    -- hypot rescales its arguments, avoiding overflow/underflow from squares.
    xy ::= hypot(.left = vector.x, .right = vector.y).result
    value = hypot(.left = xy, .right = vector.z).result
}
