-- Shared scratch representation for planar boundary editing. Stored walks keep
-- bridge uses; geometric contour views cancel paired uses within each walk.
_BoundaryErrors := choice_union#(
    .a: BuildErrors, .b: (..missing_vertex, ..unsupported_boundary)
)

_BoundaryUse := (
    .origin   : ?VertexId,
    .edge     : EdgeId,
    .reversed : Bool,
    .pcurve   : ?PCurveId  = ..none
)

implement ImplicitlyCopyable#(_BoundaryUse) ()

_BoundaryRange := (.start: UIntNative, .count: UIntNative)

implement ImplicitlyCopyable#(_BoundaryRange) ()

_boundary_use_point := #(.Scalar: Type: Float) (
    .use: _BoundaryUse, .points: &DynamicArray#(g.Point#(Scalar))
) -> (.result: Errable#(g.Point#(Scalar), _BoundaryErrors)) {
    match use.origin {
        ..none { result = ..error(.reason = ..unsupported_boundary) }
        ..some vertex {
            index ::= vertex.value | convert#(.to: UIntNative)(_)
            result = ..ok get(points, .index = index)!
        }
    }
}

_PlanarContours := #(.Scalar: Type: Float) (
    .points  : DynamicArray#(g.Point#(Scalar)),
    .lengths : DynamicArray#(UIntNative)
)

-- Each extracted contour remembers the stored walk it came from. Hole
-- assignment keeps whole walks together while validating their simple contours.
_BoundaryContours := #(.Scalar: Type: Float) (
    .points  : DynamicArray#(g.Point#(Scalar)),
    .lengths : DynamicArray#(UIntNative),
    .walks   : DynamicArray#(UIntNative)
)

-- The ranges partition uses in order. Pairing is local to each range; the edge
-- lookup is initialized once for the whole selection, including all its holes.
_boundary_contours := #(.Scalar: Type: Float, .Provider: Type: Allocator) (
    .uses       : &DynamicArray#(_BoundaryUse),
    .ranges     : ArrayView#(_BoundaryRange),
    .points     : &DynamicArray#(g.Point#(Scalar)),
    .edge_count : UIntNative,
    .allocator  : $&Provider
) -> (.result: Errable#(_BoundaryContours#(Scalar), _BoundaryErrors)) {
    count ::= length(uses).count
    first ::= DynamicArray#(UIntNative)(.allocator = allocator, .capacity = edge_count)!
    twins ::= DynamicArray#(UIntNative)(.allocator = allocator, .capacity = count)!
    next ::= DynamicArray#(UIntNative)(.allocator = allocator, .capacity = count)!
    visited ::= DynamicArray#(Bool)(.allocator = allocator, .capacity = count)!
    i :: UIntNative = 0
    while i < edge_count {
        push($&first, .value = count, .allocator = allocator)!
        i = i + 1
    }
    i = 0
    while i < count {
        push($&twins, .value = count, .allocator = allocator)!
        push($&next, .value = count, .allocator = allocator)!
        push($&visited, .value = false, .allocator = allocator)!
        i = i + 1
    }
    range_count ::= length(&ranges).count
    r :: UIntNative = 0
    cursor :: UIntNative = 0
    while r < range_count {
        range ::= get(&ranges, .index = r)!
        if range.start != cursor or range.count == 0 or range.count > count - cursor {
            result = ..error(.reason = ..invalid_region_lengths)
            return
        }
        i = range.start
        while i < range.start + range.count {
            successor ::= i + 1
            if successor == range.start + range.count { successor = range.start }
            next_slot ::= get_mutable_reference($&next, .index = i)!
            next_slot&= successor
            use ::= get(uses, .index = i)!
            edge ::= use.edge | convert#(.to: UIntNative)(_)
            previous ::= get(&first, .index = edge)!
            if previous == count {
                slot ::= get_mutable_reference($&first, .index = edge)!
                slot&= i
            } else {
                other ::= get(uses, .index = previous)!
                if get(&twins, .index = previous)! != count or other.reversed == use.reversed {
                    result = ..error(.reason = ..unsupported_boundary)
                    return
                }
                -- Opposite uses in different stored loops are not canceled.
                if previous >= range.start {
                    a ::= get_mutable_reference($&twins, .index = previous)!
                    a&= i
                    b ::= get_mutable_reference($&twins, .index = i)!
                    b&= previous
                }
            }
            i = i + 1
        }
        cursor = cursor + range.count
        r = r + 1
    }
    if cursor != count {
        result = ..error(.reason = ..invalid_region_lengths)
        return
    }
    -- Surviving uses trace disjoint paths through the canceled permutation.
    -- Bridge uses retain raw successors, so each bridge chain is crossed once.
    i = 0
    while i < count {
        if get(&twins, .index = i)! == count {
            cursor = get(&next, .index = i)!
            crossed :: UIntNative = 0
            while get(&twins, .index = cursor)! != count {
                if crossed >= count {
                    result = ..error(.reason = ..unsupported_boundary)
                    return
                }
                cursor = get(&next, .index = get(&twins, .index = cursor)!)!
                crossed = crossed + 1
            }
            slot ::= get_mutable_reference($&next, .index = i)!
            slot&= cursor
        }
        i = i + 1
    }
    coordinates ::= DynamicArray#(g.Point#(Scalar))(.allocator = allocator, .capacity = count)!
    lengths ::= DynamicArray#(UIntNative)(.allocator = allocator)!
    walks ::= DynamicArray#(UIntNative)(.allocator = allocator)!
    walk :: UIntNative = 0
    range_end :: UIntNative = 0
    i = 0
    while i < count {
        if i == range_end {
            range ::= get(&ranges, .index = walk)!
            range_end = range.start + range.count
            walk = walk + 1
        }
        if get(&twins, .index = i)! == count and get(&visited, .index = i)! == false {
            cursor = i
            length :: UIntNative = 0
            while true {
                if get(&visited, .index = cursor)! or length >= count {
                    result = ..error(.reason = ..unsupported_boundary)
                    return
                }
                slot ::= get_mutable_reference($&visited, .index = cursor)!
                slot&= true
                use ::= get(uses, .index = cursor)!
                push(
                    $&coordinates
                    .value     = _boundary_use_point(.use = use, .points = points)!
                    .allocator = allocator
                )!
                length = length + 1
                cursor = get(&next, .index = cursor)!
                if cursor == i { break }
            }
            push($&lengths, .value = length, .allocator = allocator)!
            push($&walks, .value = walk - 1, .allocator = allocator)!
        }
        i = i + 1
    }
    result = ..ok(.points = ~coordinates, .lengths = ~lengths, .walks = ~walks)
}

_walk_region := #(.Scalar: Type: Float, .Provider: Type: Allocator) (
    .uses       : &DynamicArray#(_BoundaryUse),
    .range      : _BoundaryRange,
    .points     : &DynamicArray#(g.Point#(Scalar)),
    .edge_count : UIntNative,
    .plane      : g.Plane#(Scalar),
    .positive   : Bool,
    .tolerance  : Scalar,
    .allocator  : $&Provider
) -> (.result: Errable#(_PlanarContours#(Scalar), SplitErrors)) {
    ranges: [1]_BoundaryRange = (range)
    contours ::= _boundary_contours(
        .uses       = uses
        .ranges     = view(&ranges)
        .points     = points
        .edge_count = edge_count
        .allocator  = allocator
    )!
    cycle_count ::= length(&contours.lengths).count
    cycles ::= DynamicArray#(_BoundaryRange)(.allocator = allocator, .capacity = cycle_count)!
    coordinates ::= view(&contours.points)
    outer :: UIntNative = 0
    outer_count :: UIntNative = 0
    cursor :: UIntNative = 0
    i :: UIntNative = 0
    while i < cycle_count {
        length ::= get(&contours.lengths, .index = i)!
        if length < 3 {
            result = ..error(.reason = ..degenerate_cut)
            return
        }
        contour ::= slice(&coordinates, .start = cursor, .count = length)!
        if g.contour_orientation(.points = contour, .plane = plane)! == positive {
            outer = i
            outer_count = outer_count + 1
        }
        cycle: _BoundaryRange = (.start = cursor, .count = length)
        push($&cycles, .value = cycle, .allocator = allocator)!
        cursor = cursor + length
        i = i + 1
    }
    if outer_count != 1 {
        result = ..error(.reason = ..cut_outside_face)
        return
    }
    exterior ::= get(&cycles, .index = outer)!
    initial ::= get(&cycles, .index = 0)!
    slot ::= get_mutable_reference($&cycles, .index = outer)!
    slot&= initial
    first_slot ::= get_mutable_reference($&cycles, .index = 0)!
    first_slot&= exterior
    ordered ::= DynamicArray#(g.Point#(Scalar))(.allocator = allocator, .capacity = cursor)!
    lengths ::= DynamicArray#(UIntNative)(.allocator = allocator, .capacity = cycle_count)!
    i = 0
    while i < cycle_count {
        cycle ::= get(&cycles, .index = i)!
        push($&lengths, .value = cycle.count, .allocator = allocator)!
        j :: UIntNative = 0
        while j < cycle.count {
            push(
                $&ordered
                .value     = get(&contours.points, .index = cycle.start + j)!
                .allocator = allocator
            )!
            j = j + 1
        }
        i = i + 1
    }
    region: _PlanarContours#(Scalar) = (.points = ~ordered, .lengths = ~lengths)
    _walk_validate_region(.region = &region, .tolerance = tolerance, .allocator = allocator)!
    result = ..ok ~region
}

_walk_validate_region := #(.Scalar: Type: Float, .Provider: Type: Allocator) (
    .region: &_PlanarContours#(Scalar), .tolerance: Scalar, .allocator: $&Provider
) -> (.result: Errable#(Void, BuildErrors)) {
    regions: [1]UIntNative = (
        length(&region&.lengths).count
    )
    g.planar_regions_plane(
        .points              = view(&region&.points)
        .contour_lengths     = view(&region&.lengths)
        .region_lengths      = view(&regions)
        .tolerance           = tolerance
        .require_orientation = true
        .allocator           = allocator
    )!
    result = ..ok Void()
}

_walk_validate_cut := #(.Scalar: Type: Float, .Provider: Type: Allocator) (
    .face      : Face,
    .boundary  : &_SplitBoundary,
    .points    : &DynamicArray#(g.Point#(Scalar)),
    .start     : g.Point#(Scalar),
    .end       : g.Point#(Scalar),
    .bridge    : Bool              = false,
    .plane     : g.Plane#(Scalar),
    .tolerance : Scalar,
    .allocator : $&Provider
) -> (.result: Errable#(Void, SplitErrors)) {
    coordinates ::= DynamicArray#(g.Point#(Scalar))(.allocator = allocator)!
    lengths ::= DynamicArray#(UIntNative)(.allocator = allocator, .capacity = face.loop_count)!
    first ::= face.first_loop | convert#(.to: UIntNative)(_)
    i :: UIntNative = 0
    while i < face.loop_count {
        range ::= get(&boundary&.loops, .index = first + i)!
        push($&lengths, .value = range.count, .allocator = allocator)!
        j :: UIntNative = 0
        while j < range.count {
            use ::= get(&boundary&.uses, .index = range.start + j)!
            push(
                $&coordinates
                .value     = _boundary_use_point(.use = use, .points = points)!
                .allocator = allocator
            )!
            j = j + 1
        }
        i = i + 1
    }
    if bridge {
        g.validate_planar_bridge(
            .points          = view(&coordinates)
            .contour_lengths = view(&lengths)
            .start           = start
            .end             = end
            .plane           = plane
            .tolerance       = tolerance
        )!
    } else {
        g.validate_planar_cut_contacts(
            .points          = view(&coordinates)
            .contour_lengths = view(&lengths)
            .start           = start
            .end             = end
            .plane           = plane
            .tolerance       = tolerance
        )!
    }
    result = ..ok Void()
}
