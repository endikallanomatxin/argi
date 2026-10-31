-- Copy an admitted profile onto another right-handed orthonormal frame.
-- Local spans, tolerance and region/contour/span positions remain unchanged.
-- This is rigid placement, not scaling, reflection, live attachment or B-rep
-- identity preservation. The result owns its arrays and does not borrow source.
profile_on_frame := #(.Scalar: Type: Float, .Provider: Type: Allocator) (
    .profile: &PlanarProfile#(Scalar), .frame: g.Frame#(Scalar), .allocator: $&Provider
) -> (.result: Errable#(PlanarProfile#(Scalar), t.BuildErrors)) {
    g.validate_frame(frame)!
    spans ::= _copy_profile_values(&profile&._spans, .allocator = allocator)!
    contours ::= _copy_profile_values(&profile&._contour_lengths, .allocator = allocator)!
    regions ::= _copy_profile_values(&profile&._region_lengths, .allocator = allocator)!
    result = ..ok(
        ._spans           = ~spans
        ._contour_lengths = ~contours
        ._region_lengths  = ~regions
        ._frame           = frame
        ._tolerance       = profile&._tolerance
    )
}

_copy_profile_values := #(.Value: Type: ImplicitlyCopyable, .Provider: Type: Allocator) (
    .source: &DynamicArray#(Value), .allocator: $&Provider
) -> (.result: Errable#(DynamicArray#(Value), (..out_of_memory))) {
    count ::= length(source).count
    values ::= DynamicArray#(Value)(.capacity = count, .allocator = allocator)!
    for value in source&{ push_assume_capacity($&values, .value = value) }
    result = ..ok ~values
}
