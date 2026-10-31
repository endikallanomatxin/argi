-- Start and end refer to the original and displaced profile, independently
-- of the displacement sign. They do not mean lower and upper world coordinates.
ExtrusionCaps := (.start: t.FaceId, .end: t.FaceId)

implement ImplicitlyCopyable#(ExtrusionCaps) ()

-- Source keys are positions in the supplied profile's region and span views.
-- Images belong only to this model; no borrow of the source profile is retained.
ExtrusionResult := #(.Scalar: Type: Float) (
    .model            : t.Model#(Scalar),
    ._caps            : DynamicArray#(ExtrusionCaps),
    ._walls           : DynamicArray#(t.FaceId),
    ._contour_offsets : DynamicArray#(UIntNative)
)

extrude_with_history := #(.Scalar: Type: Float, .Provider: Type: Allocator) (
    .profile      : &PlanarProfile#(Scalar),
    .displacement : g.Displacement#(Scalar),
    .allocator    : $&Provider
) -> (.result: Errable#(ExtrusionResult#(Scalar), t.BrepErrors)) {
    model ::= extrude(.profile = profile, .displacement = displacement, .allocator = allocator)!
    regions ::= length(&profile&._region_lengths).count
    spans ::= length(&profile&._spans).count
    caps ::= DynamicArray#(ExtrusionCaps)(.capacity = regions, .allocator = allocator)!
    walls ::= DynamicArray#(t.FaceId)(.capacity = spans, .allocator = allocator)!
    contours ::= length(&profile&._contour_lengths).count
    offsets ::= DynamicArray#(UIntNative)(.capacity = contours + 1, .allocator = allocator)!
    push_assume_capacity($&offsets, .value = 0)
    cursor :: UIntNative = 0
    contour :: UIntNative = 0
    while contour < contours {
        cursor = cursor + get(&profile&._contour_lengths, .index = contour)!
        push_assume_capacity($&offsets, .value = cursor)
        contour = contour + 1
    }
    -- extrude publishes original caps, translated caps, then walls in span order.
    i :: UIntNative = 0
    while i < regions {
        start ::= i | convert#(.to: t.FaceId)(_)
        end ::= [regions + i] | convert#(.to: t.FaceId)(_)
        push_assume_capacity($&caps, .value = (.start = start, .end = end))
        i = i + 1
    }
    i = 0
    while i < spans {
        wall ::= [regions * 2 + i] | convert#(.to: t.FaceId)(_)
        push_assume_capacity($&walls, .value = wall)
        i = i + 1
    }
    result = ..ok(
        .model            = ~model
        ._caps            = ~caps
        ._walls           = ~walls
        ._contour_offsets = ~offsets
    )
}

extrusion_caps := #(.Scalar: Type: Float) (
    .extrusion: &ExtrusionResult#(Scalar), .region: UIntNative
) -> (.result: Errable#(ExtrusionCaps, (..out_of_bounds))) {
    value ::= get(&extrusion&._caps, .index = region)!
    result = ..ok value
}

extrusion_wall := #(.Scalar: Type: Float) (
    .extrusion: &ExtrusionResult#(Scalar), .span: UIntNative
) -> (.result: Errable#(t.FaceId, (..out_of_bounds))) {
    value ::= get(&extrusion&._walls, .index = span)!
    result = ..ok value
}
