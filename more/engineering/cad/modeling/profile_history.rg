-- Source keys are positions in the profile's public region/contour/span views,
-- not persistent identities. Destination IDs belong only to this result.model.
-- No source borrow or reference into the result's own storage is retained.
ProfilePublication := #(.Scalar: Type: Float) (
    .model          : t.Model#(Scalar),
    ._region_faces  : DynamicArray#(t.FaceId),
    ._contour_loops : DynamicArray#(t.LoopId),
    ._span_uses     : DynamicArray#(t.HalfEdgeId)
)

-- Optional history is built after ordinary publication. Face, loop and span
-- order are preserved by profile_brep; traversal follows connectivity, without
-- assuming consecutive halfedge IDs or deriving edges from source offsets.
profile_brep_with_history := #(.Scalar: Type: Float, .Provider: Type: Allocator) (
    .profile: &PlanarProfile#(Scalar), .allocator: $&Provider
) -> (.result: Errable#(ProfilePublication#(Scalar), t.BrepErrors)) {
    model ::= profile_brep(profile, .allocator = allocator)!
    region_count ::= length(&profile&._region_lengths).count
    contour_count ::= length(&profile&._contour_lengths).count
    span_count ::= length(&profile&._spans).count
    faces ::= DynamicArray#(t.FaceId)(.capacity = region_count, .allocator = allocator)!
    loops ::= DynamicArray#(t.LoopId)(.capacity = contour_count, .allocator = allocator)!
    uses ::= DynamicArray#(t.HalfEdgeId)(.capacity = span_count, .allocator = allocator)!
    region :: UIntNative = 0
    while region < region_count {
        face ::= region | convert#(.to: t.FaceId)(_)
        push_assume_capacity($&faces, .value = face)
        for loop in t.face_loops(&model, .face = face)! {
            push_assume_capacity($&loops, .value = loop.id)
            for entry in t.loop_halfedges(&model, .loop = loop.id)! {
                push_assume_capacity($&uses, .value = entry.id)
            }
        }
        region = region + 1
    }
    result = ..ok(
        .model          = ~model
        ._region_faces  = ~faces
        ._contour_loops = ~loops
        ._span_uses     = ~uses
    )
}

published_profile_face := #(.Scalar: Type: Float) (
    .publication: &ProfilePublication#(Scalar), .region: UIntNative
) -> (.result: Errable#(t.FaceId, (..out_of_bounds))) {
    value ::= get(&publication&._region_faces, .index = region)!
    result = ..ok value
}

published_profile_loop := #(.Scalar: Type: Float) (
    .publication: &ProfilePublication#(Scalar), .contour: UIntNative
) -> (.result: Errable#(t.LoopId, (..out_of_bounds))) {
    value ::= get(&publication&._contour_loops, .index = contour)!
    result = ..ok value
}

-- The halfedge preserves directed traversal, including clockwise hole spans.
-- Its edge field identifies the shared 3D edge; use parameters follow the span.
published_profile_halfedge := #(.Scalar: Type: Float) (
    .publication: &ProfilePublication#(Scalar), .span: UIntNative
) -> (.result: Errable#(t.HalfEdgeId, (..out_of_bounds))) {
    value ::= get(&publication&._span_uses, .index = span)!
    result = ..ok value
}
