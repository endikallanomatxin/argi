-- A projected basis keeps distance tolerances in model units.
_RegionPoint := #(.Scalar: Type: Float) (.x: Scalar, .y: Scalar)

implement#(.Scalar: Type: Float) ImplicitlyCopyable#(_RegionPoint#(Scalar)) ()

_project_region_point := #(.Scalar: Type: Float) (
    .point : Point#(Scalar),
    .plane : Plane#(Scalar),
    .u     : Displacement#(Scalar),
    .v     : Displacement#(Scalar)
) -> (.result: Errable#(_RegionPoint#(Scalar), GeometryErrors)) {
    offset ::= between(.from = plane.origin, .to = point).result
    x ::= dot(.left = offset, .right = u).value
    y ::= dot(.left = offset, .right = v).value
    distance ::= dot(.left = offset, .right = plane.normal).value
    if is_finite(x).ok == false or is_finite(y).ok == false or is_finite(distance).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    result = ..ok(x, y)
}

-- Signed distance to the supporting line, with a normalized direction.
_region_side := #(.Scalar: Type: Float) (
    .a: _RegionPoint#(Scalar), .b: _RegionPoint#(Scalar), .p: _RegionPoint#(Scalar)
) -> (.result: Errable#(Scalar, GeometryErrors)) {
    dx ::= b.x - a.x
    dy ::= b.y - a.y
    magnitude ::= hypot(.left = dx, .right = dy).result
    value ::= [dx / magnitude] * [p.y - a.y] - [dy / magnitude] * [p.x - a.x]
    if is_finite(value).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    result = ..ok value
}

_region_near_segment := #(.Scalar: Type: Float) (
    .a          : _RegionPoint#(Scalar),
    .b          : _RegionPoint#(Scalar),
    .p          : _RegionPoint#(Scalar),
    .tolerance  : Scalar,
    .resolution : Scalar
) -> (.result: Errable#(Bool, GeometryErrors)) {
    dx ::= b.x - a.x
    dy ::= b.y - a.y
    magnitude ::= hypot(.left = dx, .right = dy).result
    along ::= [dx / magnitude] * [p.x - a.x] + [dy / magnitude] * [p.y - a.y]
    side ::= _region_side(.a = a, .b = b, .p = p)!
    if is_finite(along).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    distance ::= _absolute(side).result
    offset_length ::= hypot(.left = p.x - a.x, .right = p.y - a.y).result
    if along < 0.0 {
        distance = offset_length
    } else if along > magnitude {
        distance = hypot(.left = p.x - b.x, .right = p.y - b.y).result
    }
    scale ::= magnitude
    if offset_length > scale { scale = offset_length }
    budget ::= scale * resolution * 64.0
    if is_finite(distance).ok == false or is_finite(budget).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    if budget == 0.0 and scale > 0.0 {
        result = ..error(.reason = ..numerical_ambiguity)
        return
    }
    -- A definite answer requires room for roundoff on the distance as well.
    if distance + budget <= tolerance {
        result = ..ok true
        return
    }
    if distance > tolerance and distance - tolerance > budget {
        result = ..ok false
        return
    }
    result = ..error(.reason = ..numerical_ambiguity)

}

_region_segments_touch := #(.Scalar: Type: Float) (
    .a          : _RegionPoint#(Scalar),
    .b          : _RegionPoint#(Scalar),
    .c          : _RegionPoint#(Scalar),
    .d          : _RegionPoint#(Scalar),
    .tolerance  : Scalar,
    .resolution : Scalar
) -> (.result: Errable#(Bool, GeometryErrors)) {
    if [
        _region_near_segment(
            .a = a, .b = b, .p = c, .tolerance = tolerance, .resolution = resolution
        )!
        or _region_near_segment(
            .a = a, .b = b, .p = d, .tolerance = tolerance, .resolution = resolution
        )!
        or _region_near_segment(
            .a = c, .b = d, .p = a, .tolerance = tolerance, .resolution = resolution
        )!
        or _region_near_segment(
            .a = c, .b = d, .p = b, .tolerance = tolerance, .resolution = resolution
        )!
    ] {
        result = ..ok true
        return
    }
    -- Disjoint boxes rule out crossing without resolving collinear signs.
    if [
        _region_intervals_disjoint(.a = a.x, .b = b.x, .c = c.x, .d = d.x).ok
        or _region_intervals_disjoint(.a = a.y, .b = b.y, .c = c.y, .d = d.y).ok
    ] {
        result = ..ok false
        return
    }
    ac ::= _region_orientation(.a = a, .b = b, .p = c, .resolution = resolution)!
    ad ::= _region_orientation(.a = a, .b = b, .p = d, .resolution = resolution)!
    ca ::= _region_orientation(.a = c, .b = d, .p = a, .resolution = resolution)!
    cb ::= _region_orientation(.a = c, .b = d, .p = b, .resolution = resolution)!
    touches ::= [
        ac < 0 and ad > 0
        or [ac > 0 and ad < 0]
        and [[ca < 0 and cb > 0] or [ca > 0 and cb < 0]]
    ]
    result = ..ok touches
}

_region_contains := #(.Scalar: Type: Float) (
    .points     : &DynamicArray#(_RegionPoint#(Scalar)),
    .start      : UIntNative,
    .count      : UIntNative,
    .point      : _RegionPoint#(Scalar),
    .resolution : Scalar
) -> (.result: Errable#(Bool, GeometryErrors)) {
    inside ::= false
    i :: UIntNative = 0
    while i < count {
        a ::= get(points, .index = start + i)!
        b ::= get(points, .index = start + [i + 1] % count)!
        if [a.y > point.y] != [b.y > point.y] {
            side ::= _region_orientation(.a = a, .b = b, .p = point, .resolution = resolution)!
            if [side > 0] == [b.y > a.y] { inside = inside == false }
        }
        i = i + 1
    }
    result = ..ok inside
}

-- Contiguous points per contour, contiguous contours per region. The first
-- contour of each region is its exterior; subsequent contours are holes.
-- Regions may be disconnected or lie inside another region's hole.
planar_regions_plane := #(.Scalar: Type: Float, .Provider: Type: Allocator) (
    .points              : ArrayView#(Point#(Scalar)),
    .contour_lengths     : ArrayView#(UIntNative),
    .region_lengths      : ArrayView#(UIntNative),
    .tolerance           : Scalar                      = 0.000001,
    .allocator           : $&Provider,
    .require_orientation : Bool                        = false
) -> (.result: Errable#(Plane#(Scalar), GeometryErrors)) {
    if is_finite(tolerance).ok == false or tolerance <= 0.0 {
        result = ..error(.reason = ..invalid_tolerance)
        return
    }
    count ::= length(&points).count
    loops ::= length(&contour_lengths).count
    regions ::= length(&region_lengths).count
    if loops == 0 or regions == 0 {
        result = ..error(.reason = ..invalid_region_lengths)
        return
    }
    cursor :: UIntNative = 0
    contour_index :: UIntNative = 0
    while contour_index < loops {
        n ::= get(&contour_lengths, .index = contour_index)!
        contour_index = contour_index + 1
        if n < 3 {
            result = ..error(.reason = ..degenerate_face)
            return
        }
        if n > count - cursor {
            result = ..error(.reason = ..invalid_region_lengths)
            return
        }
        cursor = cursor + n
    }
    if cursor != count {
        result = ..error(.reason = ..invalid_region_lengths)
        return
    }
    cursor = 0
    region_index :: UIntNative = 0
    while region_index < regions {
        n ::= get(&region_lengths, .index = region_index)!
        region_index = region_index + 1
        if n == 0 or n > loops - cursor {
            result = ..error(.reason = ..invalid_region_lengths)
            return
        }
        cursor = cursor + n
    }
    if cursor != loops {
        result = ..error(.reason = ..invalid_region_lengths)
        return
    }
    point_index :: UIntNative = 0
    while point_index < count {
        p ::= get(&points, .index = point_index)!
        point_index = point_index + 1
        if finite_point(p).ok == false {
            result = ..error(.reason = ..invalid_coordinate)
            return
        }
    }
    plane ::= _infer_region_plane(.points = points, .tolerance = tolerance)!
    a ::= plane.origin
    normal ::= plane.normal
    u ::= _region_plane_axis(.plane = plane).result
    v ::= cross(.left = normal, .right = u).result
    i :: UIntNative = 0
    projected ::= DynamicArray#(_RegionPoint#(Scalar))(
        .allocator = allocator, .capacity = count
    )!
    point_index = 0
    while point_index < count {
        p ::= get(&points, .index = point_index)!
        point_index = point_index + 1
        offset ::= between(.from = a, .to = p).result
        distance ::= dot(.left = normal, .right = offset).value
        if is_finite(distance).ok == false {
            result = ..error(.reason = ..numeric_range)
            return
        }
        if distance > tolerance or distance < [0.0 - tolerance] {
            result = ..error(.reason = ..nonplanar_face)
            return
        }
        push(
            $&projected
            .value     = _project_region_point(.point = p, .plane = plane, .u = u, .v = v)!
            .allocator = allocator
        )!
    }
    resolution ::= _float_resolution#(Scalar)().value
    starts ::= DynamicArray#(UIntNative)(.allocator = allocator, .capacity = loops)!
    owners ::= DynamicArray#(UIntNative)(.allocator = allocator, .capacity = loops)!
    exteriors ::= DynamicArray#(UIntNative)(.allocator = allocator, .capacity = regions)!
    signs ::= DynamicArray#(Bool)(.allocator = allocator, .capacity = loops)!
    cursor = 0
    region :: UIntNative = 0
    loop :: UIntNative = 0
    while region < regions {
        push($&exteriors, .value = loop, .allocator = allocator)!
        end ::= loop + get(&region_lengths, .index = region)!
        while loop < end {
            push($&starts, .value = cursor, .allocator = allocator)!
            push($&owners, .value = region, .allocator = allocator)!
            n ::= get(&contour_lengths, .index = loop)!
            i = 0
            while i < n {
                p ::= get(&projected, .index = cursor + i)!
                q ::= get(&projected, .index = cursor + [i + 1] % n)!
                edge_length ::= hypot(.left = q.x - p.x, .right = q.y - p.y).result
                if is_finite(edge_length).ok == false {
                    result = ..error(.reason = ..numeric_range)
                    return
                }
                if edge_length <= tolerance {
                    result = ..error(.reason = ..degenerate_face)
                    return
                }
                -- Adjacent edges may continue straight, but may not fold back.
                previous ::= get(&projected, .index = cursor + [i + n - 1] % n)!
                previous_length ::= hypot(
                    .left = p.x - previous.x, .right = p.y - previous.y
                ).result
                if is_finite(previous_length).ok == false {
                    result = ..error(.reason = ..numeric_range)
                    return
                }
                if previous_length <= tolerance {
                    result = ..error(.reason = ..degenerate_face)
                    return
                }
                if [
                    _region_near_segment(
                        .a          = p
                        .b          = q
                        .p          = previous
                        .tolerance  = tolerance
                        .resolution = resolution
                    )!
                    or _region_near_segment(
                        .a          = previous
                        .b          = p
                        .p          = q
                        .tolerance  = tolerance
                        .resolution = resolution
                    )!
                ] {
                    result = ..error(.reason = ..intersecting_contours)
                    return
                }
                i = i + 1
            }
            positive ::= _region_area_positive(
                .points = &projected, .start = cursor, .count = n
            )!
            push($&signs, .value = positive, .allocator = allocator)!
            cursor = cursor + n
            loop = loop + 1
        }
        region = region + 1
    }
    -- Reject every nonadjacent segment intersection or tolerance-level touch.
    loop = 0
    while loop < loops {
        start ::= get(&starts, .index = loop)!
        n ::= get(&contour_lengths, .index = loop)!
        other ::= loop
        while other < loops {
            other_start ::= get(&starts, .index = other)!
            m ::= get(&contour_lengths, .index = other)!
            i = 0
            while i < n {
                j :: UIntNative = 0
                while j < m {
                    if loop != other or [j > i and j != [i + 1] % n and i != [j + 1] % n] {
                        if _region_segments_touch(
                            .a          = get(&projected, .index = start + i)!
                            .b          = get(&projected, .index = [start + [i + 1] % n])!
                            .c          = get(&projected, .index = other_start + j)!
                            .d          = get(&projected, .index = [other_start + [j + 1] % m])!
                            .tolerance  = tolerance
                            .resolution = resolution
                        )! {
                            result = ..error(.reason = ..intersecting_contours)
                            return
                        }
                    }
                    j = j + 1
                }
                i = i + 1
            }
            other = other + 1
        }
        loop = loop + 1
    }
    loop = 0
    while loop < loops {
        owner ::= get(&owners, .index = loop)!
        exterior ::= get(&exteriors, .index = owner)!
        p ::= get(&projected, .index = get(&starts, .index = loop)!)!
        if loop != exterior {
            if [
                _region_contains(
                    .points     = &projected
                    .start      = get(&starts, .index = exterior)!
                    .count      = get(&contour_lengths, .index = exterior)!
                    .point      = p
                    .resolution = resolution
                )!
                == false
            ] {
                result = ..error(.reason = ..invalid_region_nesting)
                return
            }
        }
        if require_orientation {
            expected ::= get(&signs, .index = exterior)!
            if loop != exterior { expected = expected == false }
            if get(&signs, .index = loop)! != expected {
                result = ..error(.reason = ..inconsistent_orientation)
                return
            }
        }
        other :: UIntNative = 0
        while other < loops {
            if other != loop and get(&owners, .index = other)! == owner and other != exterior {
                if _region_contains(
                    .points     = &projected
                    .start      = get(&starts, .index = other)!
                    .count      = get(&contour_lengths, .index = other)!
                    .point      = p
                    .resolution = resolution
                )! {
                    result = ..error(.reason = ..invalid_region_nesting)
                    return
                }
            }
            other = other + 1
        }
        if loop == exterior {
            r :: UIntNative = 0
            while r < regions {
                if r != owner {
                    first ::= get(&exteriors, .index = r)!
                    inside ::= false
                    other = first
                    while other < first + get(&region_lengths, .index = r)! {
                        if _region_contains(
                            .points     = &projected
                            .start      = get(&starts, .index = other)!
                            .count      = get(&contour_lengths, .index = other)!
                            .point      = p
                            .resolution = resolution
                        )! { inside = [inside == false] }
                        other = other + 1
                    }
                    if inside {
                        result = ..error(.reason = ..invalid_region_nesting)
                        return
                    }
                }
                r = r + 1
            }
        }
        loop = loop + 1
    }
    oriented ::= normal
    if get(&signs, .index = 0)! == false {
        oriented = (0.0 - normal.x, 0.0 - normal.y, 0.0 - normal.z)
    }
    result = ..ok(.origin = a, .normal = oriented)
}

-- Orientation relative to a validated common plane.
contour_orientation := #(.Scalar: Type: Float) (
    .points: ArrayView#(Point#(Scalar)), .plane: Plane#(Scalar)
) -> (.result: Errable#(Bool, GeometryErrors)) {
    count ::= length(&points).count
    if count < 3 {
        result = ..error(.reason = ..degenerate_face)
        return
    }
    origin ::= get(&points, .index = 0)!
    local_plane: Plane#(Scalar) = (.origin = origin, .normal = plane.normal)
    u ::= _region_plane_axis(.plane = plane).result
    v ::= cross(.left = plane.normal, .right = u).result
    scale :: Scalar = 0.0
    i :: UIntNative = 0
    while i < count {
        p ::= _project_region_point(
            .point = get(&points, .index = i)!, .plane = local_plane, .u = u, .v = v
        )!
        if _absolute(p.x).result > scale { scale = _absolute(p.x).result }
        if _absolute(p.y).result > scale { scale = _absolute(p.y).result }
        i = i + 1
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
        p ::= _project_region_point(
            .point = get(&points, .index = i)!, .plane = local_plane, .u = u, .v = v
        )!
        q ::= _project_region_point(
            .point = get(&points, .index = [i + 1] % count)!
            .plane = local_plane
            .u     = u
            .v     = v
        )!
        left ::= [p.x / scale] * [q.y / scale]
        right ::= [p.y / scale] * [q.x / scale]
        area = area + [left - right]
        magnitude = magnitude + _absolute(left).result + _absolute(right).result
        terms = terms + 1.0
        i = i + 1
    }
    result = _area_positive(.area = area, .magnitude = magnitude, .terms = terms)
}
