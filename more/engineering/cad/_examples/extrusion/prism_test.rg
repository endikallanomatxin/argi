-- Validate a planar rectangle, then extrude it with a displacement.
-- The X component makes the prism oblique. Both caps and the side faces
-- are created by the operation; their winding gives outward cap normals.
test usage_extruded_prism := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    profile: [4]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (2.0, 0.0, 0.0),
        (2.0, 1.0, 0.0),
        (0.0, 1.0, 0.0)
    )
    -- Validation produces a typed profile that the operation can consume.
    validated ::= m.profile_from_contour(.points = view(&profile))!
    model ::= m.extrude(.profile = &validated, .displacement = (0.25, 0.0, 3.0))!
    counts ::= t.entity_counts(&model)
    testing.expect(counts.vertices == 8 and counts.edges == 12 and counts.faces == 6)!
    testing.expect(t.is_closed(&model).ok)!
    bottom ::= t.face_plane(&model, .face = (.value = 0))!
    top ::= t.face_plane(&model, .face = (.value = 1))!
    testing.expect(bottom.normal.z < 0.0 and top.normal.z > 0.0)!
}
