-- Arithmetic uncertainty is separate from model-unit geometric tolerance.
-- This guard has no exact fallback: unresolved signs return an explicit error.
_float_resolution := #(.Scalar: Type: Float) () -> (.value: Scalar) {
    one: Scalar = 1.0
    value = 1.0
    half ::= value / 2.0
    while one + half > one {
        value = half
        half = value / 2.0
    }
}

_absolute := #(.Scalar: Type: Float) (.value: Scalar) -> (.result: Scalar) {
    result = value
    if result < 0.0 { result = 0.0 - result }
}

-- Sign of a 2D turn on represented projected coordinates. Common scaling
-- avoids product overflow; a conservative absolute guard rejects cancellation
-- and extreme aspect ratios. It does not certify the preceding 3D projection.
_region_orientation := #(.Scalar: Type: Float) (
    .a          : _RegionPoint#(Scalar),
    .b          : _RegionPoint#(Scalar),
    .p          : _RegionPoint#(Scalar),
    .resolution : Scalar
) -> (.result: Errable#(Int32, GeometryErrors)) {
    if [a.x == b.x and a.y == b.y] or [a.x == p.x and a.y == p.y] or [b.x == p.x and b.y == p.y] {
        result = ..ok 0
        return
    }
    if [a.x == b.x and a.x == p.x] or [a.y == b.y and a.y == p.y] {
        result = ..ok 0
        return
    }
    dx ::= b.x - a.x
    dy ::= b.y - a.y
    px ::= p.x - a.x
    py ::= p.y - a.y
    scale ::= _absolute(dx).result
    if _absolute(dy).result > scale { scale = _absolute(dy).result }
    if _absolute(px).result > scale { scale = _absolute(px).result }
    if _absolute(py).result > scale { scale = _absolute(py).result }
    if is_finite(scale).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    if scale == 0.0 {
        result = ..error(.reason = ..numerical_ambiguity)
        return
    }
    determinant ::= [dx / scale] * [py / scale] - [dy / scale] * [px / scale]
    guard ::= resolution * 32.0
    if _absolute(determinant).result <= guard {
        result = ..error(.reason = ..numerical_ambiguity)
        return
    }
    sign :: Int32 = 1
    if determinant < 0.0 { sign = -1 }
    result = ..ok sign
}

_region_area_positive := #(.Scalar: Type: Float) (
    .points: &DynamicArray#(_RegionPoint#(Scalar)), .start: UIntNative, .count: UIntNative
) -> (.result: Errable#(Bool, GeometryErrors)) {
    anchor ::= get(points, .index = start)!
    scale :: Scalar = 0.0
    i :: UIntNative = 0
    while i < count {
        p ::= get(points, .index = start + i)!
        dx ::= _absolute(p.x - anchor.x).result
        dy ::= _absolute(p.y - anchor.y).result
        if dx > scale { scale = dx }
        if dy > scale { scale = dy }
        i = i + 1
    }
    if is_finite(scale).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    if scale == 0.0 {
        result = ..error(.reason = ..degenerate_face)
        return
    }
    area :: Scalar = 0.0
    magnitude :: Scalar = 0.0
    terms :: Scalar = 0.0
    i = 0
    while i < count {
        p ::= get(points, .index = start + i)!
        q ::= get(points, .index = start + [i + 1] % count)!
        left ::= [[p.x - anchor.x] / scale] * [[q.y - anchor.y] / scale]
        right ::= [[p.y - anchor.y] / scale] * [[q.x - anchor.x] / scale]
        area = area + [left - right]
        magnitude = magnitude + _absolute(left).result + _absolute(right).result
        terms = terms + 1.0
        i = i + 1
    }
    result = _area_positive(.area = area, .magnitude = magnitude, .terms = terms)
}

_region_intervals_disjoint := #(.Scalar: Type: Float) (
    .a: Scalar, .b: Scalar, .c: Scalar, .d: Scalar
) -> (.ok: Bool) {
    low ::= a
    high ::= b
    if a > b {
        low = b
        high = a
    }
    ok = [c < low and d < low] or [c > high and d > high]
}

_area_positive := #(.Scalar: Type: Float) (.area: Scalar, .magnitude: Scalar, .terms: Scalar) -> (
    .result : Errable#(Bool, GeometryErrors)
) {
    if is_finite(area).ok == false or is_finite(magnitude).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    if magnitude == 0.0 {
        result = ..error(.reason = ..degenerate_face)
        return
    }
    guard ::= _float_resolution#(Scalar)().value * 32.0 * terms * magnitude
    if _absolute(area).result <= guard {
        result = ..error(.reason = ..numerical_ambiguity)
        return
    }
    positive ::= area > 0.0
    result = ..ok positive
}
