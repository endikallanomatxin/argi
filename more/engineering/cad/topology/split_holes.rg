-- Extract geometric hole contours once for all unjoined stored walks. A walk
-- may contain internal bridge pieces after fusion; those pieces stay stored.
_split_hole_contours := #(.Scalar: Type: Float) (
    .face       : Face,
    .boundary   : &_SplitBoundary,
    .points     : &DynamicArray#(g.Point#(Scalar)),
    .edge_count : UIntNative,
    .allocator  : $&Virtual#(Allocator)
) -> (.result: Errable#(_BoundaryContours#(Scalar), SplitErrors)) {

    count ::= face.loop_count - 1
    if count == 0 {
        coordinates ::= DynamicArray#(g.Point#(Scalar))(.allocator = allocator)!
        lengths ::= DynamicArray#(UIntNative)(.allocator = allocator)!
        walks ::= DynamicArray#(UIntNative)(.allocator = allocator)!
        result = ..ok(.points = ~coordinates, .lengths = ~lengths, .walks = ~walks)
        return
    }
    uses ::= DynamicArray#(_BoundaryUse)(.allocator = allocator)!
    ranges ::= DynamicArray#(_BoundaryRange)(.allocator = allocator, .capacity = count)!
    first ::= face.first_loop | convert#(.to: UIntNative)(_)
    i :: UIntNative = 0
    while i < count {
        source ::= get(&boundary&.loops, .index = first + 1 + i)!
        start ::= length(&uses).count
        j :: UIntNative = 0
        while j < source.count {
            push(
                $&uses
                .value     = get(&boundary&.uses, .index = source.start + j)!
                .allocator = allocator
            )!
            j = j + 1
        }
        range: _BoundaryRange = (.start = start, .count = source.count)
        push($&ranges, .value = range, .allocator = allocator)!
        i = i + 1
    }
    contours ::= _boundary_contours(
        .uses       = &uses
        .ranges     = view(&ranges)
        .points     = points
        .edge_count = edge_count
        .allocator  = allocator
    )!
    result = ..ok ~contours
}

-- One boolean per stored hole walk, in source order. Choose a representative
-- from its geometric contours, never from a canceled internal bridge tip.
_split_partition_holes := #(.Scalar: Type: Float) (
    .holes      : &_BoundaryContours#(Scalar),
    .hole_count : UIntNative,
    .exterior   : ArrayView#(g.Point#(Scalar)),
    .plane      : g.Plane#(Scalar),
    .tolerance  : Scalar,
    .allocator  : $&Virtual#(Allocator)
) -> (.result: Errable#(DynamicArray#(Bool), SplitErrors)) {

    owners ::= DynamicArray#(Bool)(.allocator = allocator, .capacity = hole_count)!
    seen ::= DynamicArray#(Bool)(.allocator = allocator, .capacity = hole_count)!
    i :: UIntNative = 0
    while i < hole_count {
        push($&owners, .value = false, .allocator = allocator)!
        push($&seen, .value = false, .allocator = allocator)!
        i = i + 1
    }
    count ::= length(&holes&.lengths).count
    cursor :: UIntNative = 0
    i = 0
    while i < count {
        walk ::= get(&holes&.walks, .index = i)!
        if get(&seen, .index = walk)! == false {
            position ::= get(&holes&.points, .index = cursor)!
            owner ::= false
            match g.locate_in_planar_contour(
                .points = exterior, .point = position, .plane = plane, .tolerance = tolerance
            )! {
                ..inside { owner = true }
                ..outside {}
                ..boundary {
                    result = ..error(.reason = ..intersecting_contours)
                    return
                }
            }
            slot ::= get_mutable_reference($&owners, .index = walk)!
            slot&= owner
            seen_slot ::= get_mutable_reference($&seen, .index = walk)!
            seen_slot&= true
        }
        cursor = cursor + get(&holes&.lengths, .index = i)!
        i = i + 1
    }
    i = 0
    while i < hole_count {
        if get(&seen, .index = i)! == false {
            result = ..error(.reason = ..unsupported_boundary)
            return
        }
        i = i + 1
    }
    result = ..ok ~owners
}

_split_validate_region := #(.Scalar: Type: Float) (
    .holes     : &_BoundaryContours#(Scalar),
    .exterior  : &_PlanarContours#(Scalar),
    .owners    : &DynamicArray#(Bool),
    .first     : Bool,
    .tolerance : Scalar,
    .allocator : $&Virtual#(Allocator)
) -> (.result: Errable#(Void, SplitErrors)) {

    count ::= length(&holes&.lengths).count
    if count == 0 {
        result = ..ok Void()
        return
    }
    coordinates ::= copy(&exterior&.points, .allocator = allocator)!
    lengths ::= copy(&exterior&.lengths, .allocator = allocator)!
    cursor :: UIntNative = 0
    i :: UIntNative = 0
    while i < count {
        length ::= get(&holes&.lengths, .index = i)!
        walk ::= get(&holes&.walks, .index = i)!
        if get(owners, .index = walk)! == first {
            push($&lengths, .value = length, .allocator = allocator)!
            j :: UIntNative = 0
            while j < length {
                push(
                    $&coordinates
                    .value     = get(&holes&.points, .index = cursor + j)!
                    .allocator = allocator
                )!
                j = j + 1
            }
        }
        cursor = cursor + length
        i = i + 1
    }
    region: _PlanarContours#(Scalar) = (.points = ~coordinates, .lengths = ~lengths)
    _walk_validate_region(.region = &region, .tolerance = tolerance, .allocator = allocator)!
    result = ..ok Void()
}
