-- An owning immutable analytic planar region set. Spans are contiguous per
-- contour; each region starts with an exterior followed by clockwise holes.
PlanarProfile := #(.Scalar: Type: Float) (
    ._spans           : DynamicArray#(g.ContourSpan#(Scalar)),
    ._contour_lengths : DynamicArray#(UIntNative),
    ._region_lengths  : DynamicArray#(UIntNative),
    ._frame           : g.Frame#(Scalar),
    ._tolerance       : Scalar
)

planar_profile := #(.Scalar: Type: Float) (
    .points          : ArrayView#(g.Point#(Scalar)),
    .contour_lengths : ArrayView#(UIntNative),
    .region_lengths  : ArrayView#(UIntNative),
    .tolerance       : Scalar                        = 0.000001,
    .allocator       : Virtual#(Allocator)
) -> (.result: Errable#(PlanarProfile#(Scalar), t.BuildErrors)) {

    plane ::= g.planar_regions_plane#(.Scalar: Scalar)(
        .points          = points
        .contour_lengths = contour_lengths
        .region_lengths  = region_lengths
        .tolerance       = tolerance
        .allocator       = allocator
    )!
    frame ::= g.frame(.origin = plane.origin, .axis = plane.normal)!
    owned ::= DynamicArray#(g.ContourSpan#(Scalar))(
        .allocator = allocator, .capacity = length(&points).count
    )!
    contours ::= DynamicArray#(UIntNative)(
        .allocator = allocator, .capacity = length(&contour_lengths).count
    )!
    regions ::= DynamicArray#(UIntNative)(
        .allocator = allocator, .capacity = length(&region_lengths).count
    )!
    cursor :: UIntNative = 0
    loop :: UIntNative = 0
    region_index :: UIntNative = 0
    while region_index < length(&region_lengths).count {
        n ::= get(&region_lengths, .index = region_index)!
        region_index = region_index + 1
        push($&regions, .value = n, .allocator = allocator)!
        local_loop :: UIntNative = 0
        while local_loop < n {
            count ::= get(&contour_lengths, .index = loop)!
            ring ::= slice(&points, .start = cursor, .count = count)!
            positive ::= g.contour_orientation(.points = ring, .plane = plane)!
            reverse ::= positive != [local_loop == 0]
            i :: UIntNative = 0
            while i < count {
                source ::= i
                if reverse { source = count - 1 - i }
                point ::= g.project_on_plane(
                    .point = get(&ring, .index = source)!, .plane = plane
                )!
                next_index ::= [i + 1] % count
                if reverse { next_index = count - 1 - next_index }
                next ::= g.project_on_plane(
                    .point = get(&ring, .index = next_index)!, .plane = plane
                )!
                span: g.ContourSpan#(Scalar) = (
                    .start = _profile_chart_point(.frame = frame, .point = point)!
                    .end   = _profile_chart_point(.frame = frame, .point = next)!
                )
                push_assume_capacity($&owned, .value = span)
                i = i + 1
            }
            push($&contours, .value = count, .allocator = allocator)!
            cursor = cursor + count
            loop = loop + 1
            local_loop = local_loop + 1
        }
    }
    result = ..ok(
        ._spans           = ~owned
        ._contour_lengths = ~contours
        ._region_lengths  = ~regions
        ._frame           = frame
        ._tolerance       = tolerance
    )
}

profile_from_contour := #(.Scalar: Type: Float) (
    .points: ArrayView#(g.Point#(Scalar)), .tolerance: Scalar = 0.000001, .allocator: Virtual#(Allocator)
) -> (.result: Errable#(PlanarProfile#(Scalar), t.BuildErrors)) {
    contours :: [1]UIntNative = (
        length(&points).count
    )
    regions :: [1]UIntNative = (1)
    contour_view ::= view(&contours)
    region_view ::= view(&regions)
    built ::= planar_profile(
        .points          = points
        .contour_lengths = contour_view
        .region_lengths  = region_view
        .tolerance       = tolerance
        .allocator       = allocator
    )!
    result = ..ok ~built
}

-- One exterior followed by holes, already oriented in the supplied frame.
-- This constructor admits analytic segments and circular arcs without sampling.
profile_from_spans := #(.Scalar: Type: Float) (
    .spans           : ArrayView#(g.ContourSpan#(Scalar)),
    .contour_lengths : ArrayView#(UIntNative),
    .frame           : g.Frame#(Scalar),
    .tolerance       : Scalar                  = 0.000001,
    .allocator       : Virtual#(Allocator)
) -> (.result: Errable#(PlanarProfile#(Scalar), t.BuildErrors)) {
    g.validate_frame(frame)!
    g.validate_contour_region(
        .spans = spans, .lengths = contour_lengths, .tolerance = tolerance
    )!
    count ::= length(&spans).count
    loops ::= length(&contour_lengths).count
    owned ::= DynamicArray#(g.ContourSpan#(Scalar))(.capacity = count, .allocator = allocator)!
    contours ::= DynamicArray#(UIntNative)(.capacity = loops, .allocator = allocator)!
    regions ::= DynamicArray#(UIntNative)(.capacity = 1, .allocator = allocator)!
    i :: UIntNative = 0
    while i < count {
        push_assume_capacity($&owned, .value = get(&spans, .index = i)!)
        i = i + 1
    }
    i = 0
    while i < loops {
        push_assume_capacity($&contours, .value = get(&contour_lengths, .index = i)!)
        i = i + 1
    }
    push_assume_capacity($&regions, .value = loops)
    result = ..ok(
        ._spans           = ~owned
        ._contour_lengths = ~contours
        ._region_lengths  = ~regions
        ._frame           = frame
        ._tolerance       = tolerance
    )
}

profile_spans := #(.Scalar: Type: Float) (.profile: &PlanarProfile#(Scalar)) -> (
    .spans : ArrayView#(g.ContourSpan#(Scalar))
) {
    spans = view(&profile&._spans)
}

profile_contour_lengths := #(.Scalar: Type: Float) (.profile: &PlanarProfile#(Scalar)) -> (
    .lengths : ArrayView#(UIntNative)
) {
    lengths = view(&profile&._contour_lengths)
}

profile_region_lengths := #(.Scalar: Type: Float) (.profile: &PlanarProfile#(Scalar)) -> (
    .lengths : ArrayView#(UIntNative)
) {
    lengths = view(&profile&._region_lengths)
}

profile_frame := #(.Scalar: Type: Float) (.profile: &PlanarProfile#(Scalar)) -> (
    .frame : g.Frame#(Scalar)
) {
    frame = profile&._frame
}

profile_plane := #(.Scalar: Type: Float) (.profile: &PlanarProfile#(Scalar)) -> (
    .plane : g.Plane#(Scalar)
) {
    plane = (.origin = profile&._frame.origin, .normal = profile&._frame.z)
}

profile_tolerance := #(.Scalar: Type: Float) (.profile: &PlanarProfile#(Scalar)) -> (
    .value : Scalar
) {
    value = profile&._tolerance
}

-- World-space start of a directed span; this does not flatten curved spans.
profile_point := #(.Scalar: Type: Float) (.profile: &PlanarProfile#(Scalar), .index: UIntNative) -> (
    .result : Errable#(g.Point#(Scalar), (..out_of_bounds, ..numeric_range))
) {
    span ::= get(&profile&._spans, .index = index)!
    value ::= _profile_world_point(.frame = profile&._frame, .point = span.start).value
    if g.finite_point(value).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    result = ..ok value
}

_profile_chart_point := #(.Scalar: Type: Float) (
    .frame: g.Frame#(Scalar), .point: g.Point#(Scalar)
) -> (.result: Errable#(g.ContourPoint#(Scalar), (..numeric_range))) {
    offset ::= g.between(.from = frame.origin, .to = point).result
    x ::= g.dot(.left = frame.x, .right = offset).value
    y ::= g.dot(.left = frame.y, .right = offset).value
    if is_finite(x).ok == false or is_finite(y).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    result = ..ok(x, y)
}

_profile_world_point := #(.Scalar: Type: Float) (
    .frame: g.Frame#(Scalar), .point: g.ContourPoint#(Scalar)
) -> (.value: g.Point#(Scalar)) {
    value = (
        .x = frame.origin.x + frame.x.x * point.x + frame.y.x * point.y
        .y = frame.origin.y + frame.x.y * point.x + frame.y.y * point.y
        .z = frame.origin.z + frame.x.z * point.x + frame.y.z * point.y
    )
}
