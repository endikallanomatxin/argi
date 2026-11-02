-- Directed chart boundary. Sweep zero denotes a segment. A nonzero sweep
-- denotes a circular arc about center, with |sweep| <= one turn, in radians.
-- This geometric representation has no topological identities. Profiles may
-- own spans; B-rep admission uses temporary spans without storing a second region.
ContourPoint := #(.Scalar: Type: Float) (.x: Scalar, .y: Scalar)

implement#(.Scalar: Type: Float) ImplicitlyCopyable#(ContourPoint#(Scalar)) ()

ContourSpan := #(.Scalar: Type: Float) (
    .start  : ContourPoint#(Scalar),
    .end    : ContourPoint#(Scalar),
    .center : ContourPoint#(Scalar)  = (0.0, 0.0),
    .sweep  : Scalar                 = 0.0
)

implement#(.Scalar: Type: Float) ImplicitlyCopyable#(ContourSpan#(Scalar)) ()

_contour_distance := #(.Scalar: Type: Float) (
    .a: ContourPoint#(Scalar), .b: ContourPoint#(Scalar)
) -> (.value: Scalar) {
    value = hypot(.left = a.x - b.x, .right = a.y - b.y).result
}

_contour_cross := #(.Scalar: Type: Float) (
    .a: ContourPoint#(Scalar), .b: ContourPoint#(Scalar), .p: ContourPoint#(Scalar)
) -> (.value: Scalar) {
    value = [b.x - a.x] * [p.y - a.y] - [b.y - a.y] * [p.x - a.x]
}

_contour_point := #(.Scalar: Type: Float) (.span: ContourSpan#(Scalar), .parameter: Scalar) -> (
    .point : ContourPoint#(Scalar)
) {
    if span.sweep == 0.0 {
        point = (
            .x = [1.0 - parameter] * span.start.x + parameter * span.end.x
            .y = [[1.0 - parameter] * span.start.y + parameter * span.end.y]
        )
        return
    }
    angle ::= span.sweep * parameter
    x ::= span.start.x - span.center.x
    y ::= span.start.y - span.center.y
    c ::= cos(angle).result
    s ::= sin(angle).result
    point = (span.center.x + x * c - y * s, span.center.y + x * s + y * c)
}

-- Angular membership uses oriented vectors, with no inverse trig or branch cut.
_contour_on_arc := #(.Scalar: Type: Float) (
    .span: ContourSpan#(Scalar), .point: ContourPoint#(Scalar), .tolerance: Scalar
) -> (.ok: Bool) {
    radius ::= _contour_distance(.a = span.start, .b = span.center).value
    a ::= _contour_cross(.a = span.center, .b = span.start, .p = point).value
    b ::= _contour_cross(.a = span.center, .b = point, .p = span.end).value
    sweep ::= span.sweep
    if sweep < 0.0 {
        a = 0.0 - a
        b = 0.0 - b
        sweep = 0.0 - sweep
    }
    guard ::= tolerance * radius
    ok = a >= [0.0 - guard] and b >= [0.0 - guard]
    if sweep > 3.141592653589793 { ok = a >= [0.0 - guard] or b >= [0.0 - guard] }
    if sweep == 6.283185307179586 { ok = true }
}

_contour_on_span := #(.Scalar: Type: Float) (
    .span: ContourSpan#(Scalar), .point: ContourPoint#(Scalar), .tolerance: Scalar
) -> (.ok: Bool) {
    if span.sweep != 0.0 {
        radius ::= _contour_distance(.a = span.start, .b = span.center).value
        distance ::= _contour_distance(.a = point, .b = span.center).value
        ok = [
            _absolute(distance - radius).result <= tolerance
            and _contour_on_arc(.span = span, .point = point, .tolerance = tolerance).ok
        ]
        return
    }
    dx ::= span.end.x - span.start.x
    dy ::= span.end.y - span.start.y
    length ::= hypot(.left = dx, .right = dy).result
    along ::= [[point.x - span.start.x] * dx + [point.y - span.start.y] * dy] / length
    side ::= _contour_cross(.a = span.start, .b = span.end, .p = point).value / length
    ok = [
        along >= [0.0 - tolerance]
        and along <= length + tolerance
        and _absolute(side).result <= tolerance
    ]
}

_validate_contour_span := #(.Scalar: Type: Float) (
    .span: ContourSpan#(Scalar), .tolerance: Scalar
) -> (.result: Errable#(Void, GeometryErrors)) {
    if [
        is_finite(span.start.x).ok == false
        or is_finite(span.start.y).ok == false
        or is_finite(span.end.x).ok == false
        or is_finite(span.end.y).ok == false
        or is_finite(span.center.x).ok == false
        or is_finite(span.center.y).ok == false
        or is_finite(span.sweep).ok == false
    ] {
        result = ..error(.reason = ..invalid_coordinate)
        return
    }
    scale ::= [
        _absolute(span.start.x).result
        + _absolute(span.start.y).result
        + _absolute(span.end.x).result
        + _absolute(span.end.y).result
        + _absolute(span.center.x).result
        + _absolute(span.center.y).result
    ]
    if is_finite(scale * scale).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    if scale * _float_resolution#(Scalar)().value > tolerance {
        result = ..error(.reason = ..numerical_ambiguity)
        return
    }
    length ::= _contour_distance(.a = span.start, .b = span.end).value
    if span.sweep != 0.0 {
        radius ::= _contour_distance(.a = span.start, .b = span.center).value
        if radius <= tolerance or _absolute(span.sweep).result > 6.283185307179586 {
            result = ..error(.reason = ..degenerate_face)
            return
        }
        expected ::= _contour_point(.span = span, .parameter = 1.0).point
        if _contour_distance(.a = expected, .b = span.end).value > tolerance {
            result = ..error(.reason = ..invalid_surface)
            return
        }
        length = radius * _absolute(span.sweep).result
    }
    if is_finite(length).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    if length <= tolerance {
        result = ..error(.reason = ..degenerate_face)
        return
    }
    result = ..ok Void()
}
