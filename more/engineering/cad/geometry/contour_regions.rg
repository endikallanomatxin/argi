-- One exterior followed by holes. Geometric admission is independent of any
-- surface or B-rep connectivity. Pair tests are quadratic in the number of
-- analytic spans
-- no tessellation or persistent acceleration index is used.
validate_contour_region := #(.Scalar: Type: Float) (
    .spans     : ArrayView#(ContourSpan#(Scalar)),
    .lengths   : ArrayView#(UIntNative),
    .tolerance : Scalar                  = 0.000001,
    .reversed  : Bool                    = false
) -> (.result: Errable#(Void, GeometryErrors)) {
    if is_finite(tolerance).ok == false or tolerance <= 0.0 {
        result = ..error(.reason = ..invalid_tolerance)
        return
    }
    count ::= length(&spans).count
    loops ::= length(&lengths).count
    if count == 0 or loops == 0 {
        result = ..error(.reason = ..invalid_region_lengths)
        return
    }
    first :: UIntNative = 0
    l :: UIntNative = 0
    while l < loops {
        n ::= get(&lengths, .index = l)!
        if n == 0 or n > count - first {
            result = ..error(.reason = ..invalid_region_lengths)
            return
        }
        area :: Scalar = 0.0
        i :: UIntNative = 0
        while i < n {
            span ::= get(&spans, .index = first + i)!
            _validate_contour_span(.span = span, .tolerance = tolerance)!
            next ::= get(&spans, .index = first + [i + 1] % n)!
            if _contour_distance(.a = span.end, .b = next.start).value > tolerance {
                result = ..error(.reason = ..invalid_region_lengths)
                return
            }
            -- Integrate x dy - y dx relative to a local anchor.
            anchor ::= get(&spans, .index = first)!.start
            area = [
                area
                + [span.start.x - anchor.x] * [span.end.y - anchor.y]
                - [span.start.y - anchor.y] * [span.end.x - anchor.x]
            ]
            if span.sweep != 0.0 {
                r ::= _contour_distance(.a = span.start, .b = span.center).value
                area = area + r * r * [span.sweep - sin(span.sweep).result]
            }
            j :: UIntNative = 0
            while j < first + i {
                other ::= get(&spans, .index = j)!
                adjacent ::= [j >= first and j + 1 == first + i] or [j == first and i + 1 == n]
                _contour_pair(
                    .a = other, .b = span, .adjacent = adjacent, .tolerance = tolerance
                )!
                j = j + 1
            }
            i = i + 1
        }
        if is_finite(area).ok == false {
            result = ..error(.reason = ..numeric_range)
            return
        }
        if _absolute(area).result <= tolerance * tolerance {
            result = ..error(.reason = ..degenerate_face)
            return
        }
        positive ::= [l == 0] != reversed
        if [area > 0.0] != positive {
            result = ..error(.reason = ..inconsistent_orientation)
            return
        }
        first = first + n
        l = l + 1
    }
    if first != count {
        result = ..error(.reason = ..invalid_region_lengths)
        return
    }
    -- Once boundaries are disjoint, one point determines containment of a loop.
    first = get(&lengths, .index = 0)!
    l = 1
    while l < loops {
        point ::= get(&spans, .index = first)!.start
        offset :: UIntNative = 0
        j :: UIntNative = 0
        while j < l {
            n ::= get(&lengths, .index = j)!
            view ::= slice(&spans, .start = offset, .count = n)!
            location ::= locate_in_contour_spans(
                .spans = view, .point = point, .tolerance = tolerance
            )!
            acceptable ::= false
            match location {
                ..inside { acceptable = j == 0 }
                ..outside { acceptable = j > 0 }
                ..boundary {}
            }
            if acceptable == false {
                result = ..error(.reason = ..invalid_region_nesting)
                return
            }
            offset = offset + n
            j = j + 1
        }
        -- Earlier holes cannot be inside this hole either.
        n ::= get(&lengths, .index = l)!
        view ::= slice(&spans, .start = first, .count = n)!
        offset = get(&lengths, .index = 0)!
        j = 1
        while j < l {
            location ::= locate_in_contour_spans(
                .spans     = view
                .point     = get(&spans, .index = offset)!.start
                .tolerance = tolerance
            )!
            match location {
                ..outside {}
                ..inside {
                    result = ..error(.reason = ..invalid_region_nesting)
                    return
                }
                ..boundary {
                    result = ..error(.reason = ..invalid_region_nesting)
                    return
                }
            }
            offset = offset + get(&lengths, .index = j)!
            j = j + 1
        }
        first = first + n
        l = l + 1
    }
    result = ..ok Void()
}
