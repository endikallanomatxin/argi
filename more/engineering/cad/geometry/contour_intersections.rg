-- Contact candidates are computed analytically. Adjacent spans may meet only
-- at their shared endpoint; any other contact invalidates the simple contour.
_contour_contact := #(.Scalar: Type: Float) (
    .a         : ContourSpan#(Scalar),
    .b         : ContourSpan#(Scalar),
    .point     : ContourPoint#(Scalar),
    .adjacent  : Bool,
    .tolerance : Scalar
) -> (.result: Errable#(Void, GeometryErrors)) {
    if [
        _contour_on_span(.span = a, .point = point, .tolerance = tolerance).ok
        and _contour_on_span(.span = b, .point = point, .tolerance = tolerance).ok
    ] {
        if adjacent {
            if [
                [
                    _contour_distance(.a = point, .b = a.end).value <= tolerance
                    and _contour_distance(.a = point, .b = b.start).value <= tolerance
                ]
                or [
                    _contour_distance(.a = point, .b = a.start).value <= tolerance
                    and _contour_distance(.a = point, .b = b.end).value <= tolerance
                ]
            ] {
                result = ..ok Void()
                return
            }
        }
        result = ..error(.reason = ..intersecting_contours)
        return
    }
    result = ..ok Void()
}

_contour_pair := #(.Scalar: Type: Float) (
    .a: ContourSpan#(Scalar), .b: ContourSpan#(Scalar), .adjacent: Bool, .tolerance: Scalar
) -> (.result: Errable#(Void, GeometryErrors)) {
    -- Endpoint proximity must be checked even when infinite supports do not meet.
    _contour_contact(
        .a = a, .b = b, .point = a.start, .adjacent = adjacent, .tolerance = tolerance
    )!
    _contour_contact(
        .a = a, .b = b, .point = a.end, .adjacent = adjacent, .tolerance = tolerance
    )!
    _contour_contact(
        .a = a, .b = b, .point = b.start, .adjacent = adjacent, .tolerance = tolerance
    )!
    _contour_contact(
        .a = a, .b = b, .point = b.end, .adjacent = adjacent, .tolerance = tolerance
    )!
    if a.sweep == 0.0 and b.sweep == 0.0 {
        dx ::= a.end.x - a.start.x
        dy ::= a.end.y - a.start.y
        ex ::= b.end.x - b.start.x
        ey ::= b.end.y - b.start.y
        denominator ::= dx * ey - dy * ex
        scale ::= hypot(.left = dx, .right = dy).result * hypot(.left = ex, .right = ey).result
        if _absolute(denominator).result <= scale * _float_resolution#(Scalar)().value * 64.0 {
            if denominator != 0.0 {
                result = ..error(.reason = ..numerical_ambiguity)
                return
            }
            midpoint ::= _contour_point(.span = a, .parameter = 0.5).point
            _contour_contact(
                .a = a, .b = b, .point = midpoint, .adjacent = false, .tolerance = tolerance
            )!
            midpoint_b ::= _contour_point(.span = b, .parameter = 0.5).point
            _contour_contact(
                .a = a, .b = b, .point = midpoint_b, .adjacent = false, .tolerance = tolerance
            )!
            -- Endpoint and interior checks catch collinear overlap.
            result = ..ok Void()
            return
        }
        parameter ::= [
            [b.start.x - a.start.x] * ey
            - [b.start.y - a.start.y] * ex / denominator
        ]
        point: ContourPoint#(Scalar) = (
            .x = a.start.x + parameter * dx
            .y = [a.start.y + parameter * dy]
        )
        result = _contour_contact(
            .a = a, .b = b, .point = point, .adjacent = adjacent, .tolerance = tolerance
        )
        return
    }
    if a.sweep == 0.0 {
        result = _contour_line_circle(
            .line = a, .arc = b, .adjacent = adjacent, .tolerance = tolerance
        )
        return
    }
    if b.sweep == 0.0 {
        result = _contour_line_circle(
            .line = b, .arc = a, .adjacent = adjacent, .tolerance = tolerance
        )
        return
    }
    r ::= _contour_distance(.a = a.start, .b = a.center).value
    s ::= _contour_distance(.a = b.start, .b = b.center).value
    distance ::= _contour_distance(.a = a.center, .b = b.center).value
    if distance < _absolute(r - s).result - tolerance {
        result = ..ok Void()
        return
    }
    if distance <= tolerance {
        if _absolute(r - s).result <= tolerance {
            -- Shared-circle subdivisions are allowed only when their interiors
            -- are disjoint; endpoints alone cannot detect coincident full arcs.
            mid_a ::= _contour_point(.span = a, .parameter = 0.5).point
            mid_b ::= _contour_point(.span = b, .parameter = 0.5).point
            _contour_contact(
                .a = a, .b = b, .point = mid_a, .adjacent = false, .tolerance = tolerance
            )!
            _contour_contact(
                .a = a, .b = b, .point = mid_b, .adjacent = false, .tolerance = tolerance
            )!
            result = ..ok Void()
            return
        }
        result = ..error(.reason = ..numerical_ambiguity)
        return
    }
    if distance > r + s + tolerance or distance < _absolute(r - s).result - tolerance {
        result = ..ok Void()
        return
    }
    along ::= [r * r - s * s + distance * distance] / [2.0 * distance]
    square ::= r * r - along * along
    if is_finite(square).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    if square < 0.0 {
        result = ..error(.reason = ..numerical_ambiguity)
        return
    }
    h ::= sqrt(square).result
    x ::= [b.center.x - a.center.x] / distance
    y ::= [b.center.y - a.center.y] / distance
    p: ContourPoint#(Scalar) = (
        .x = a.center.x + along * x - h * y
        .y = [a.center.y + along * y + h * x]
    )
    q: ContourPoint#(Scalar) = (
        .x = a.center.x + along * x + h * y
        .y = [a.center.y + along * y - h * x]
    )
    _contour_contact(.a = a, .b = b, .point = p, .adjacent = adjacent, .tolerance = tolerance)!
    _contour_contact(.a = a, .b = b, .point = q, .adjacent = adjacent, .tolerance = tolerance)!
    result = ..ok Void()
}

_contour_line_circle := #(.Scalar: Type: Float) (
    .line: ContourSpan#(Scalar), .arc: ContourSpan#(Scalar), .adjacent: Bool, .tolerance: Scalar
) -> (.result: Errable#(Void, GeometryErrors)) {
    dx ::= line.end.x - line.start.x
    dy ::= line.end.y - line.start.y
    length ::= hypot(.left = dx, .right = dy).result
    x ::= dx / length
    y ::= dy / length
    along ::= [arc.center.x - line.start.x] * x + [arc.center.y - line.start.y] * y
    side ::= [arc.center.y - line.start.y] * x - [arc.center.x - line.start.x] * y
    r ::= _contour_distance(.a = arc.center, .b = arc.start).value
    if _absolute(side).result > r + tolerance {
        result = ..ok Void()
        return
    }
    square ::= r * r - side * side
    if is_finite(square).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    if square < 0.0 {
        result = ..error(.reason = ..numerical_ambiguity)
        return
    }
    h ::= sqrt(square).result
    p: ContourPoint#(Scalar) = (
        .x = line.start.x + [along - h] * x
        .y = [line.start.y + [along - h] * y]
    )
    q: ContourPoint#(Scalar) = (
        .x = line.start.x + [along + h] * x
        .y = [line.start.y + [along + h] * y]
    )
    _contour_contact(
        .a = line, .b = arc, .point = p, .adjacent = adjacent, .tolerance = tolerance
    )!
    _contour_contact(
        .a = line, .b = arc, .point = q, .adjacent = adjacent, .tolerance = tolerance
    )!
    result = ..ok Void()
}
