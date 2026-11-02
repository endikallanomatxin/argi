-- Geometric contours are a temporary admission view. The emitted loops still
-- contain both uses of every surviving bridge and preserve its correspondence.
_merge_validate_contours := #(.Scalar: Type: Float) (
    .contours  : &_BoundaryContours#(Scalar),
    .plane     : g.Plane#(Scalar),
    .tolerance : Scalar,
    .allocator : Virtual#(Allocator)
) -> (.result: Errable#(Void, MergeErrors)) {

    count ::= length(&contours&.lengths).count
    ranges ::= DynamicArray#(_BoundaryRange)(.allocator = allocator, .capacity = count)!
    points ::= view(&contours&.points)
    outer :: UIntNative = 0
    outer_count :: UIntNative = 0
    cursor :: UIntNative = 0
    i :: UIntNative = 0
    while i < count {
        length ::= get(&contours&.lengths, .index = i)!
        contour ::= slice(&points, .start = cursor, .count = length)!
        if g.contour_orientation(.points = contour, .plane = plane)! {
            outer = i
            outer_count = outer_count + 1
        }
        range: _BoundaryRange = (.start = cursor, .count = length)
        push($&ranges, .value = range, .allocator = allocator)!
        cursor = cursor + length
        i = i + 1
    }
    if outer_count != 1 {
        result = ..error(.reason = ..invalid_merge_boundary)
        return
    }
    exterior ::= get(&ranges, .index = outer)!
    initial ::= get(&ranges, .index = 0)!
    slot ::= get_mutable_reference($&ranges, .index = outer)!
    slot&= initial
    first_slot ::= get_mutable_reference($&ranges, .index = 0)!
    first_slot&= exterior
    ordered ::= DynamicArray#(g.Point#(Scalar))(.allocator = allocator, .capacity = cursor)!
    lengths ::= DynamicArray#(UIntNative)(.allocator = allocator, .capacity = count)!
    i = 0
    while i < count {
        range ::= get(&ranges, .index = i)!
        push($&lengths, .value = range.count, .allocator = allocator)!
        j :: UIntNative = 0
        while j < range.count {
            push(
                $&ordered
                .value     = get(&contours&.points, .index = range.start + j)!
                .allocator = allocator
            )!
            j = j + 1
        }
        i = i + 1
    }
    region: _PlanarContours#(Scalar) = (.points = ~ordered, .lengths = ~lengths)
    _walk_validate_region(.region = &region, .tolerance = tolerance, .allocator = allocator)!
    result = ..ok Void()
}
