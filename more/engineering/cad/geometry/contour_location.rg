-- Ray parity for validated mixed contours. Circular intersections are analytic;
-- half-open endpoint rules count a shared vertex once, tangencies zero times.
locate_in_contour_spans := #(.Scalar: Type: Float) (
    .spans     : ArrayView#(ContourSpan#(Scalar)),
    .point     : ContourPoint#(Scalar),
    .tolerance : Scalar                 = 0.000001
) -> (.result: Errable#(ContourLocation, GeometryErrors)) {
    if is_finite(point.x).ok == false or is_finite(point.y).ok == false {
        result = ..error(.reason = ..invalid_coordinate)
        return
    }
    if is_finite(tolerance).ok == false or tolerance <= 0.0 {
        result = ..error(.reason = ..invalid_tolerance)
        return
    }
    count ::= length(&spans).count
    inside ::= false
    i :: UIntNative = 0
    while i < count {
        span ::= get(&spans, .index = i)!
        if _contour_on_span(.span = span, .point = point, .tolerance = tolerance).ok {
            result = ..ok ..boundary
            return
        }
        if span.sweep == 0.0 {
            if [span.start.y > point.y] != [span.end.y > point.y] {
                crossing ::= [
                    span.start.x
                    + [
                        point.y
                        - [
                            span.start.y
                            * [span.end.x - span.start.x]
                            / [span.end.y - span.start.y]
                        ]
                    ]
                ]
                if crossing > point.x { inside = inside == false }
            }
        } else {
            radius ::= _contour_distance(.a = span.start, .b = span.center).value
            dy ::= point.y - span.center.y
            if _absolute(dy).result < radius {
                square ::= [radius - dy] * [radius + dy]
                if is_finite(square).ok == false {
                    result = ..error(.reason = ..numeric_range)
                    return
                }
                dx ::= sqrt(square).result
                roots: [2]Scalar = (span.center.x - dx, span.center.x + dx)
                j :: UIntNative = 0
                while j < 2 {
                    x ::= roots[j]
                    candidate: ContourPoint#(Scalar) = (x, point.y)
                    -- A reconstructed arc endpoint can fall just outside its
                    -- angular sector after trig rounding. Resolve endpoint
                    -- ownership before the strict interior angular test.
                    at_start ::= [
                        _contour_distance(.a = candidate, .b = span.start).value
                        <= tolerance
                    ]
                    at_end ::= [
                        _contour_distance(.a = candidate, .b = span.end).value
                        <= tolerance
                    ]
                    if [
                        x > point.x
                        and [
                            at_start
                            or at_end
                            or _contour_on_arc(
                                .span = span, .point = candidate, .tolerance = 0.0
                            ).ok
                        ]
                    ] {
                        upward ::= [x > span.center.x] == [span.sweep > 0.0]
                        if [
                            at_start == false and at_end == false
                            or [at_start and upward]
                            or [at_end and upward == false]
                        ] {
                            inside = inside == false
                        }
                    }
                    j = j + 1
                }
            }
        }
        i = i + 1
    }
    if inside { result = ..ok ..inside } else { result = ..ok ..outside }
}
