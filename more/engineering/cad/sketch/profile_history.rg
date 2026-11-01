-- One compact source-contour record also describes the reversed span range.
-- No per-span map is needed: holes reverse the order and direction of spans.
ProfileContourImage := (
    .contour    : UIntNative,
    .first_span : UIntNative,
    .span_count : UIntNative,
    .reversed   : Bool
)

implement ImplicitlyCopyable#(ProfileContourImage) ()

ProfileSpanImage := (.span: UIntNative, .reversed: Bool)

implement ImplicitlyCopyable#(ProfileSpanImage) ()

-- The profile owns its geometry. Only history borrows the drawing's domain,
-- so checked ContourRef inputs cannot silently come from another drawing.
-- Admitted contours are nonempty; span_count zero marks an unselected source
-- contour internally. The dense map uses O(drawing contours) space and O(1)
-- queries, including when only a subset is selected.
ProfileSelection := #(.Scalar: Type: Float) (
    .profile   : m.PlanarProfile#(Scalar),
    ._source   : &idx.IndexDomain,
    ._contours : DynamicArray#(ProfileContourImage)
)

profile_with_history := #(.Scalar: Type: Float) (
    .sketch: &Sketch#(Scalar), .exterior: ContourRef, .allocator: $&Virtual#(Allocator)
) -> (.result: Errable#(ProfileSelection#(Scalar), t.BuildErrors)) {
    order ::= _profile_all_contours(sketch, .exterior = exterior, .allocator = allocator)!
    selection ::= _profile_selection(sketch, .order = view(&order), .allocator = allocator)!
    result = ..ok ~selection
}

profile_from_contours_with_history := #(.Scalar: Type: Float) (
    .sketch: &Sketch#(Scalar), .contours: ArrayView#(ContourRef), .allocator: $&Virtual#(Allocator)
) -> (.result: Errable#(ProfileSelection#(Scalar), t.BuildErrors)) {
    order ::= _profile_explicit_contours(sketch, .contours = contours, .allocator = allocator)!
    selection ::= _profile_selection(sketch, .order = view(&order), .allocator = allocator)!
    result = ..ok ~selection
}

_profile_selection := #(.Scalar: Type: Float) (
    .sketch: &Sketch#(Scalar), .order: ArrayView#(UIntNative), .allocator: $&Virtual#(Allocator)
) -> (.result: Errable#(ProfileSelection#(Scalar), t.BuildErrors)) {
    selected ::= _profile_from_order(sketch, .order = order, .allocator = allocator)!
    count ::= contour_count(sketch).count
    mapping ::= DynamicArray#(ProfileContourImage)(.capacity = count, .allocator = allocator)!
    i :: UIntNative = 0
    while i < count {
        push_assume_capacity(
            $&mapping
            .value = (.contour = 0, .first_span = 0, .span_count = 0, .reversed = false)
        )
        i = i + 1
    }
    first :: UIntNative = 0
    i = 0
    while i < length(&order).count {
        offset ::= get(&order, .index = i)!
        source ::= get(&sketch&._contours, .index = offset)!
        image: ProfileContourImage = (
            .contour    = i
            .first_span = first
            .span_count = source.count
            .reversed   = [i != 0]
        )
        target ::= get_mutable_reference($&mapping, .index = offset)!
        target&= image
        first = first + source.count
        i = i + 1
    }
    result = ..ok(
        .profile   = ~selected
        ._source   = &sketch&._domain
        ._contours = ~mapping
    )
}

profile_contour_image := #(.Scalar: Type: Float) (
    .selection: &ProfileSelection#(Scalar), .contour: ContourRef
) -> (.result: Errable#(ProfileContourImage, (..wrong_domain, ..out_of_bounds, ..not_selected))) {
    offset ::= idx.resolve_index(.domain = selection&._source, .index = contour._index)!
    image ::= get(&selection&._contours, .index = offset)!
    if image.span_count == 0 {
        result = ..error(.reason = ..not_selected)
        return
    }
    result = ..ok image
}

-- The parameter on the selected span is 1-t when reversed, otherwise t.
profile_span_image := #(.Scalar: Type: Float) (
    .selection: &ProfileSelection#(Scalar), .contour: ContourRef, .span: UIntNative
) -> (.result: Errable#(ProfileSpanImage, (..wrong_domain, ..out_of_bounds, ..not_selected))) {
    image ::= profile_contour_image(selection, .contour = contour)!
    if span >= image.span_count {
        result = ..error(.reason = ..out_of_bounds)
        return
    }
    local ::= span
    if image.reversed { local = image.span_count - 1 - span }
    result = ..ok(.span = image.first_span + local, .reversed = image.reversed)
}
