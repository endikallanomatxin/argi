-- A complete torus needs no trimming boundary or artificial seam edge.
-- Its analytic support uses a frame and two radii. A genus-one face represents
-- the whole surface; traversing its boundary therefore visits no loops.
test usage_periodic_surfaces := (.system: System) -> !() {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    frame ::= [
        g.frame#(Float64)(.origin = (0.0, 0.0, 0.0), .axis = (0.0, 0.0, 1.0))!
    ]
    support: g.Surface#(Float64) = ..torus(
        .frame        = frame
        .major_radius = 3.0
        .minor_radius = 1.0
    )
    model ::= t.from_periodic_surface(.surface = support)!
    testing.expect(t.entity_counts(&model).faces == 1 and t.entity_counts(&model).edges == 0)!
    testing.expect([t.face_info(&model, .face = (.value = 0))!].genus == 1)!
    visited :: UIntNative = 0
    for boundary in [t.face_loops(&model, .face = (.value = 0))!] {
        visited = [visited + 1]
    }
    testing.expect(visited == 0)!
}
