-- A profile can contain disconnected regions.
-- Here each triangle is one contour and one region. One extrusion produces
-- both disconnected closed components in the same immutable model.
test usage_extruded_disconnected_regions := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    points: [6]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (0.0, 1.0, 0.0),
        (3.0, 0.0, 0.0),
        (4.0, 0.0, 0.0),
        (3.0, 1.0, 0.0)
    )
    contour_lengths: [2]UIntNative = (3, 3)
    region_lengths: [2]UIntNative = (1, 1)
    profile ::= [
        m.planar_profile(
            .points          = view(&points)
            .contour_lengths = view(&contour_lengths)
            .region_lengths  = view(&region_lengths)
        )!
    ]
    model ::= m.extrude(.profile = &profile, .displacement = (0.0, 0.0, 2.0))!
    counts ::= t.entity_counts(&model)
    testing.expect(counts.vertices == 12 and counts.faces == 10)!
    testing.expect(t.is_closed(&model).ok)!
}
