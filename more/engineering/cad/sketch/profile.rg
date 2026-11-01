m := import ("../modeling")

-- Select one declared contour as exterior; every other declared contour is a
-- hole. Output order is exterior first, then remaining source contours in order.
profile := #(.Scalar: Type: Float) (
    .sketch: &Sketch#(Scalar), .exterior: ContourRef, .allocator: $&Virtual#(Allocator)
) -> (.result: Errable#(m.PlanarProfile#(Scalar), t.BuildErrors)) {
    order ::= _profile_all_contours(sketch, .exterior = exterior, .allocator = allocator)!
    selected ::= _profile_from_order(sketch, .order = view(&order), .allocator = allocator)!
    result = ..ok ~selected
}

-- Explicit selection: exterior first, then holes in caller order. All other
-- drawing contours are ignored; the reusable drawing is never modified.
profile_from_contours := #(.Scalar: Type: Float) (
    .sketch: &Sketch#(Scalar), .contours: ArrayView#(ContourRef), .allocator: $&Virtual#(Allocator)
) -> (.result: Errable#(m.PlanarProfile#(Scalar), t.BuildErrors)) {
    order ::= _profile_explicit_contours(sketch, .contours = contours, .allocator = allocator)!
    selected ::= _profile_from_order(sketch, .order = view(&order), .allocator = allocator)!
    result = ..ok ~selected
}

_profile_all_contours := #(.Scalar: Type: Float) (
    .sketch: &Sketch#(Scalar), .exterior: ContourRef, .allocator: $&Virtual#(Allocator)
) -> (.result: Errable#(DynamicArray#(UIntNative), t.BuildErrors)) {
    outer ::= idx.resolve_index(.domain = &sketch&._domain, .index = exterior._index)!
    get(&sketch&._contours, .index = outer)!
    count ::= contour_count(sketch).count
    order ::= DynamicArray#(UIntNative)(.capacity = count, .allocator = allocator)!
    push_assume_capacity($&order, .value = outer)
    i :: UIntNative = 0
    while i < count {
        if i != outer { push_assume_capacity($&order, .value = i) }
        i = i + 1
    }
    result = ..ok ~order
}

_profile_explicit_contours := #(.Scalar: Type: Float) (
    .sketch: &Sketch#(Scalar), .contours: ArrayView#(ContourRef), .allocator: $&Virtual#(Allocator)
) -> (.result: Errable#(DynamicArray#(UIntNative), t.BuildErrors)) {
    count ::= length(&contours).count
    if count == 0 {
        result = ..error(.reason = ..invalid_region_lengths)
        return
    }
    order ::= DynamicArray#(UIntNative)(.capacity = count, .allocator = allocator)!
    i :: UIntNative = 0
    while i < count {
        reference ::= get(&contours, .index = i)!
        offset ::= idx.resolve_index(.domain = &sketch&._domain, .index = reference._index)!
        get(&sketch&._contours, .index = offset)!
        push_assume_capacity($&order, .value = offset)
        i = i + 1
    }
    result = ..ok ~order
}

-- Both public paths share geometry assembly and admission. Hole winding reverses
-- span order and direction, without tessellation or arrangement inference.
_profile_from_order := #(.Scalar: Type: Float) (
    .sketch: &Sketch#(Scalar), .order: ArrayView#(UIntNative), .allocator: $&Virtual#(Allocator)
) -> (.result: Errable#(m.PlanarProfile#(Scalar), t.BuildErrors)) {
    count ::= length(&order).count
    span_count :: UIntNative = 0
    i :: UIntNative = 0
    while i < count {
        record ::= get(&sketch&._contours, .index = get(&order, .index = i)!)!
        if record.count > integer_limits(.value = span_count).maximum - span_count {
            result = ..error(.reason = ..numeric_range)
            return
        }
        span_count = span_count + record.count
        i = i + 1
    }
    spans ::= DynamicArray#(g.ContourSpan#(Scalar))(
        .capacity = span_count, .allocator = allocator
    )!
    lengths ::= DynamicArray#(UIntNative)(.capacity = count, .allocator = allocator)!
    i = 0
    while i < count {
        record ::= get(&sketch&._contours, .index = get(&order, .index = i)!)!
        push_assume_capacity($&lengths, .value = record.count)
        j :: UIntNative = 0
        while j < record.count {
            index ::= j
            if i > 0 { index = record.count - 1 - j }
            span ::= get(&sketch&._spans, .index = record.start + index)!
            if i > 0 {
                start ::= span.start
                span.start = span.end
                span.end = start
                span.sweep = 0.0 - span.sweep
            }
            push_assume_capacity($&spans, .value = span)
            j = j + 1
        }
        i = i + 1
    }
    selected ::= m.profile_from_spans(
        .spans           = view(&spans)
        .contour_lengths = view(&lengths)
        .frame           = sketch&._frame
        .tolerance       = sketch&._tolerance
        .allocator       = allocator
    )!
    result = ..ok ~selected
}
