t := import ("../topology")
g := import ("../geometry")

_ExtrusionBuffers := #(.Scalar: Type: Float) (
    .points     : DynamicArray#(g.Point#(Scalar)),
    .indices    : DynamicArray#(UIntNative),
    .lengths    : DynamicArray#(UIntNative),
    .face_loops : DynamicArray#(UIntNative)
)

-- Every connected profile region produces a separate closed volume.
_extrusion_buffers := #(.Scalar: Type: Float, .Provider: Type: Allocator) (
    .profile      : &PlanarProfile#(Scalar),
    .displacement : g.Displacement#(Scalar),
    .allocator    : $&Provider
) -> (.result: Errable#(_ExtrusionBuffers#(Scalar), t.BrepErrors)) {
    tolerance ::= profile&._tolerance
    if [
        is_finite(displacement.x).ok == false
        or is_finite(displacement.y).ok == false
        or is_finite(displacement.z).ok == false
    ] {
        result = ..error(.reason = ..invalid_coordinate)
        return
    }
    height ::= g.dot(.left = profile&._frame.z, .right = displacement).value
    if is_finite(height).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    if height <= tolerance and height >= [0.0 - tolerance] {
        result = ..error(.reason = ..degenerate_face)
        return
    }
    count ::= length(&profile&._spans).count
    loops ::= length(&profile&._contour_lengths).count
    regions ::= length(&profile&._region_lengths).count
    span_index :: UIntNative = 0
    while span_index < count {
        span ::= get(&profile&._spans, .index = span_index)!
        if span.sweep != 0.0 {
            result = ..error(.reason = ..unsupported_boundary)
            return
        }
        span_index = span_index + 1
    }
    maximum ::= integer_limits(.value = count).maximum
    if count > maximum / 6 {
        result = ..error(.reason = ..numeric_range)
        return
    }
    points ::= DynamicArray#(g.Point#(Scalar))(.allocator = allocator, .capacity = count * 2)!
    indices ::= DynamicArray#(UIntNative)(.allocator = allocator, .capacity = count * 6)!
    lengths ::= DynamicArray#(UIntNative)(.allocator = allocator, .capacity = loops * 2 + count)!
    face_loops ::= DynamicArray#(UIntNative)(
        .allocator = allocator, .capacity = [regions * 2 + count]
    )!
    point_index :: UIntNative = 0
    while point_index < count {
        p ::= profile_point(profile, .index = point_index)!
        push($&points, .value = p, .allocator = allocator)!
        point_index = point_index + 1
    }
    point_index = 0
    while point_index < count {
        p ::= profile_point(profile, .index = point_index)!
        point_index = point_index + 1
        translated: g.Point#(Scalar) = (
            .x = p.x + displacement.x
            .y = p.y + displacement.y
            .z = [p.z + displacement.z]
        )
        if g.finite_point(translated).ok == false {
            result = ..error(.reason = ..numeric_range)
            return
        }
        push($&points, .value = translated, .allocator = allocator)!
    }
    -- Keep each cap as one face per region, including its hole loops.
    layer :: UIntNative = 0
    while layer < 2 {
        cursor :: UIntNative = 0
        loop :: UIntNative = 0
        region_index :: UIntNative = 0
        while region_index < regions {
            n ::= get(&profile&._region_lengths, .index = region_index)!
            push($&face_loops, .value = n, .allocator = allocator)!
            region_index = region_index + 1
        }
        while loop < loops {
            size ::= get(&profile&._contour_lengths, .index = loop)!
            i :: UIntNative = 0
            reverse ::= [layer == 0] == [height > 0.0]
            while i < size {
                source ::= i
                if reverse { source = size - 1 - i }
                push(
                    $&indices, .value = layer * count + cursor + source, .allocator = allocator
                )!
                i = i + 1
            }
            push($&lengths, .value = size, .allocator = allocator)!
            cursor = cursor + size
            loop = loop + 1
        }
        layer = layer + 1
    }
    cursor :: UIntNative = 0
    loop_index :: UIntNative = 0
    while loop_index < loops {
        size ::= get(&profile&._contour_lengths, .index = loop_index)!
        loop_index = loop_index + 1
        i :: UIntNative = 0
        while i < size {
            a ::= cursor + i
            b ::= cursor + [i + 1] % size
            if height < 0.0 {
                temporary ::= a
                a = b
                b = temporary
            }
            push($&indices, .value = a, .allocator = allocator)!
            push($&indices, .value = b, .allocator = allocator)!
            push($&indices, .value = count + b, .allocator = allocator)!
            push($&indices, .value = count + a, .allocator = allocator)!
            push($&lengths, .value = 4, .allocator = allocator)!
            push($&face_loops, .value = 1, .allocator = allocator)!
            i = i + 1
        }
        cursor = cursor + size
    }
    result = ..ok(
        .points     = ~points
        .indices    = ~indices
        .lengths    = ~lengths
        .face_loops = ~face_loops
    )
}

-- Face order is original caps by region, translated caps by region, then
-- walls by directed profile span. Optional operation history uses this order.
extrude := #(.Scalar: Type: Float, .Provider: Type: Allocator) (
    .profile      : &PlanarProfile#(Scalar),
    .displacement : g.Displacement#(Scalar),
    .allocator    : $&Provider
) -> (.result: Errable#(t.Model#(Scalar), t.BrepErrors)) {
    buffers ::= _extrusion_buffers(
        .profile = profile, .displacement = displacement, .allocator = allocator
    )!
    point_view ::= view(&buffers.points)
    index_view ::= view(&buffers.indices)
    length_view ::= view(&buffers.lengths)
    loop_view ::= view(&buffers.face_loops)
    built ::= t.from_planar_faces(
        .points           = point_view
        .vertex_indices   = index_view
        .contour_lengths  = length_view
        .face_loop_counts = loop_view
        .tolerance        = profile&._tolerance
        .allocator        = allocator
    )!
    result = ..ok ~built
}
