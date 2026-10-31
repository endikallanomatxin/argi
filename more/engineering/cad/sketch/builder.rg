g := import ("../geometry")
t := import ("../topology")
idx := import ("../storage")

ContourId := (.value: UIntNative)

ContourRef := (._index: idx.Index#(ContourId))

implement ImplicitlyCopyable#(ContourRef) ()

SketchPlane := (..xy, ..xz, ..yz)

implement ImplicitlyCopyable#(SketchPlane) ()

_Contour := (.start: UIntNative, .count: UIntNative)

implement ImplicitlyCopyable#(_Contour) ()

SketchBuilder := #(.Scalar: Type: Float = Float32) (
    ._domain    : idx.IndexDomain,
    ._spans     : DynamicArray#(g.ContourSpan#(Scalar)),
    ._contours  : DynamicArray#(_Contour),
    ._frame     : g.Frame#(Scalar),
    ._tolerance : Scalar
)

-- An immutable drawing of explicit closed contours, not a solved constraint
-- system or an arrangement discovered from intersecting sketch entities.
Sketch := #(.Scalar: Type: Float) (
    ._domain    : idx.IndexDomain,
    ._spans     : DynamicArray#(g.ContourSpan#(Scalar)),
    ._contours  : DynamicArray#(_Contour),
    ._frame     : g.Frame#(Scalar),
    ._tolerance : Scalar
)

SketchBuilderInitArgs := #(.Scalar: Type: Float, .Provider: Type: Allocator) (
    .plane     : SketchPlane      = ..xy,
    .origin    : g.Point#(Scalar) = (0.0, 0.0, 0.0),
    .tolerance : Scalar           = 0.000001,
    .allocator : $&Provider
)

implement#(.Scalar: Type: Float, .Provider: Type: Allocator) Init#(
    SketchBuilder#(Scalar), SketchBuilderInitArgs#(Scalar, Provider)
) (
    .Result : Type = Errable#(SketchBuilder#(Scalar), t.BuildErrors)
    .init   = SketchBuilderInitArgs#(Scalar, Provider) -> (.result: Result) {
        frame: g.Frame#(Scalar) = (
            .origin = origin, .x = (1.0, 0.0, 0.0), .y = (0.0, 1.0, 0.0), .z = (0.0, 0.0, 1.0)
        )
        match plane {
            ..xy {}
            ..xz {
                frame.y = (0.0, 0.0, 1.0)
                frame.z = (0.0, -1.0, 0.0)
            }
            ..yz {
                frame.x = (0.0, 1.0, 0.0)
                frame.y = (0.0, 0.0, 1.0)
                frame.z = (1.0, 0.0, 0.0)
            }
        }
        builder ::= sketch_builder_on_frame(
            .frame = frame, .tolerance = tolerance, .allocator = allocator
        )!
        result = ..ok ~builder
    }
)

-- The frame fixes origin, local X/Y axes and normal. It must be right-handed
-- and orthonormal; placement is never silently normalized, scaled or reflected.
sketch_builder_on_frame := #(.Scalar: Type: Float, .Provider: Type: Allocator) (
    .frame: g.Frame#(Scalar), .tolerance: Scalar = 0.000001, .allocator: $&Provider
) -> (.result: Errable#(SketchBuilder#(Scalar), t.BuildErrors)) {
    if is_finite(tolerance).ok == false or tolerance <= 0.0 {
        result = ..error(.reason = ..invalid_tolerance)
        return
    }
    g.validate_frame(frame)!
    domain ::= idx.IndexDomain(.allocator = allocator)!
    spans ::= DynamicArray#(g.ContourSpan#(Scalar))(.allocator = allocator)!
    contours ::= DynamicArray#(_Contour)(.allocator = allocator)!
    result = ..ok(
        ._domain    = ~domain
        ._spans     = ~spans
        ._contours  = ~contours
        ._frame     = frame
        ._tolerance = tolerance
    )
}

-- Explicit directed spans form one counterclockwise contour. Validate before
-- reserving and appending, so rejected geometry leaves logical contents intact.
contour := #(.Scalar: Type: Float, .Provider: Type: Allocator) (
    .builder   : $&SketchBuilder#(Scalar),
    .spans     : ArrayView#(g.ContourSpan#(Scalar)),
    .allocator : $&Provider
) -> (.result: Errable#(ContourRef, t.BuildErrors)) {
    count ::= length(&spans).count
    lengths: [1]UIntNative = (count,)
    g.validate_contour_region(
        .spans = spans, .lengths = view(&lengths), .tolerance = builder&._tolerance
    )!
    start ::= length(&builder&._spans).count
    offset ::= length(&builder&._contours).count
    maximum ::= integer_limits(.value = offset).maximum
    if count > maximum - start or offset == maximum {
        result = ..error(.reason = ..numeric_range)
        return
    }
    ensure_capacity(
        .self = $&builder&._spans, .capacity = start + count, .allocator = allocator
    )!
    ensure_capacity(
        .self = $&builder&._contours, .capacity = offset + 1, .allocator = allocator
    )!
    i :: UIntNative = 0
    while i < count {
        push_assume_capacity($&builder&._spans, .value = get(&spans, .index = i)!)
        i = i + 1
    }
    push_assume_capacity($&builder&._contours, .value = (.start = start, .count = count))
    result = ..ok(
        ._index = idx.bind_index#(ContourId)(
            .domain = &builder&._domain, .offset = offset
        ).value
    )
}

finish_sketch := #(.Scalar: Type: Float) (.builder: SketchBuilder#(Scalar)) -> (
    .result : Errable#(Sketch#(Scalar), t.BuildErrors)
) {
    if length(&builder._contours).count == 0 {
        result = ..error(.reason = ..invalid_region_lengths)
        return
    }
    result = ..ok(
        ._domain    = ~builder._domain
        ._spans     = ~builder._spans
        ._contours  = ~builder._contours
        ._frame     = builder._frame
        ._tolerance = builder._tolerance
    )
}

contour_count := #(.Scalar: Type: Float) (.sketch: &Sketch#(Scalar)) -> (.count: UIntNative) {
    count = length(&sketch&._contours).count
}

contour_spans := #(.Scalar: Type: Float) (.sketch: &Sketch#(Scalar), .contour: ContourRef) -> (
    .result : Errable#(ArrayView#(g.ContourSpan#(Scalar)), t.BuildErrors)
) {
    index ::= idx.resolve_index(.domain = &sketch&._domain, .index = contour._index)!
    record ::= get(&sketch&._contours, .index = index)!
    all ::= view(&sketch&._spans)
    spans ::= slice(&all, .start = record.start, .count = record.count)!
    result = ..ok spans
}

implement Convert#(UIntNative, ContourId) (
    .Result  : Type = ContourId
    .convert = (.value: UIntNative) -> (.result: Result) { result = (.value = value) }
)

implement Convert#(ContourId, UIntNative) (
    .Result  : Type = UIntNative
    .convert = (.value: ContourId) -> (.result: Result) { result = value.value }
)

implement Equal#(ContourId, ContourId) (
    .equal = (.left: ContourId, .right: ContourId) -> (.ok: Bool) {
        ok = [left.value == right.value]
    }
)
