-- Check contacts against validated boundary walks, including bridge segments.
-- This does not classify the segment interior or select its topological side.
-- Both selected endpoints must already occur as vertices in those walks.
validate_planar_cut_contacts := #(.Scalar: Type: Float) (
    .points          : ArrayView#(Point#(Scalar)),
    .contour_lengths : ArrayView#(UIntNative),
    .start           : Point#(Scalar),
    .end             : Point#(Scalar),
    .plane           : Plane#(Scalar),
    .tolerance       : Scalar                      = 0.000001
) -> (.result: Errable#(Void, GeometryErrors)) {
    if is_finite(tolerance).ok == false or tolerance <= 0.0 {
        result = ..error(.reason = ..invalid_tolerance)
        return
    }
    basis ::= frame(.origin = plane.origin, .axis = plane.normal)!
    normalized: Plane#(Scalar) = (.origin = plane.origin, .normal = basis.z)
    a ::= _location_projection(
        .point = start, .plane = normalized, .u = basis.x, .v = basis.y, .tolerance = tolerance
    )!
    b ::= _location_projection(
        .point = end, .plane = normalized, .u = basis.x, .v = basis.y, .tolerance = tolerance
    )!
    length ::= hypot(.left = b.x - a.x, .right = b.y - a.y).result
    if is_finite(length).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    if length <= tolerance {
        result = ..error(.reason = ..degenerate_face)
        return
    }
    resolution ::= _float_resolution#(Scalar)().value
    total ::= length(&points).count
    contours ::= length(&contour_lengths).count
    cursor :: UIntNative = 0
    loop :: UIntNative = 0
    if contours < 1 {
        result = ..error(.reason = ..invalid_region_lengths)
        return
    }
    while loop < contours {
        count ::= get(&contour_lengths, .index = loop)!
        if count < 3 or count > total - cursor {
            result = ..error(.reason = ..invalid_region_lengths)
            return
        }
        i :: UIntNative = 0
        while i < count {
            c ::= _location_projection(
                .point     = get(&points, .index = cursor + i)!
                .plane     = normalized
                .u         = basis.x
                .v         = basis.y
                .tolerance = tolerance
            )!
            d ::= _location_projection(
                .point     = get(&points, .index = cursor + [i + 1] % count)!
                .plane     = normalized
                .u         = basis.x
                .v         = basis.y
                .tolerance = tolerance
            )!
            c_start ::= c.x == a.x and c.y == a.y
            c_end ::= c.x == b.x and c.y == b.y
            d_start ::= d.x == a.x and d.y == a.y
            d_end ::= d.x == b.x and d.y == b.y
            incident ::= c_start or c_end or d_start or d_end
            touches ::= false
            if incident {
                other ::= c
                endpoint ::= a
                opposite ::= b
                if c_start or c_end { other = d }
                if c_end or d_end {
                    endpoint = b
                    opposite = a
                }
                touches = _region_near_segment(
                    .a = a, .b = b, .p = other, .tolerance = tolerance, .resolution = resolution
                )!
                if touches == false {
                    touches = _region_near_segment(
                        .a          = endpoint
                        .b          = other
                        .p          = opposite
                        .tolerance  = tolerance
                        .resolution = resolution
                    )!
                }
            } else {
                touches = _region_segments_touch(
                    .a          = a
                    .b          = b
                    .c          = c
                    .d          = d
                    .tolerance  = tolerance
                    .resolution = resolution
                )!
            }
            if touches {
                result = ..error(.reason = ..intersecting_contours)
                return
            }
            i = i + 1
        }
        cursor = cursor + count
        loop = loop + 1
    }
    if cursor != total {
        result = ..error(.reason = ..invalid_region_lengths)
        return
    }
    result = ..ok Void()
}

-- Joining different boundary walks must also keep the segment inside the region.
validate_planar_bridge := #(.Scalar: Type: Float) (
    .points          : ArrayView#(Point#(Scalar)),
    .contour_lengths : ArrayView#(UIntNative),
    .start           : Point#(Scalar),
    .end             : Point#(Scalar),
    .plane           : Plane#(Scalar),
    .tolerance       : Scalar                      = 0.000001
) -> (.result: Errable#(Void, GeometryErrors)) {
    contours ::= length(&contour_lengths).count
    if contours < 2 {
        result = ..error(.reason = ..invalid_region_lengths)
        return
    }
    validate_planar_cut_contacts(
        .points          = points
        .contour_lengths = contour_lengths
        .start           = start
        .end             = end
        .plane           = plane
        .tolerance       = tolerance
    )!
    -- Once intersections are excluded, one interior sample identifies the whole
    -- open segment's region. The two endpoints themselves lie on its boundary.
    midpoint: Point#(Scalar) = (
        .x = 0.5 * start.x + 0.5 * end.x
        .y = 0.5 * start.y + 0.5 * end.y
        .z = 0.5 * start.z + 0.5 * end.z
    )
    cursor :: UIntNative = 0
    loop :: UIntNative = 0
    while loop < contours {
        count ::= get(&contour_lengths, .index = loop)!
        contour ::= slice(&points, .start = cursor, .count = count)!
        location ::= _locate_in_planar_walk(
            .points = contour, .point = midpoint, .plane = plane, .tolerance = tolerance
        )!
        if [loop == 0 and location != ..inside] or [loop != 0 and location != ..outside] {
            result = ..error(.reason = ..invalid_region_nesting)
            return
        }
        cursor = cursor + count
        loop = loop + 1
    }
    result = ..ok Void()
}
