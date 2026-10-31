-- Split the top face of the shared pocket fixture, preserving its hole.
-- pocket.rg defines the input geometry. This example focuses on selecting
-- boundary positions, inspecting the result and merging the two faces again.
test usage_split_closed_face_with_hole := (.system: System) -> !() {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    source ::= _closed_pocket(.allocator = allocator)!
    exterior ::= [
        t.loop_info(&source, .loop = [t.face_loop(&source, .face = (.value = 0))!])!
    ]
    -- Select positions on opposite edges of the exterior boundary.
    cut_start ::= exterior.first
    next ::= [t.halfedge_info(&source, .halfedge = cut_start)!].next
    cut_end ::= [t.halfedge_info(&source, .halfedge = next)!].next
    split ::= [
        t.split_planar_face(
            &source
            .face  = (.value = 0)
            .start = (.halfedge = cut_start, .parameter = 0.125)
            .end   = (.halfedge = cut_end, .parameter = 0.875)
        )!
    ]
    before ::= t.entity_counts(&source)
    after ::= t.entity_counts(&split.model)
    testing.expect(t.is_closed(&split.model).ok)!
    testing.expect(after.vertices == before.vertices + 2 and after.edges == before.edges + 3)!
    testing.expect(after.faces == before.faces + 1 and after.loops == before.loops + 1)!
    [
        testing.expect([[t.face_info(&split.model, .face = split.faces[0])!].loop_count == 2])!
    ]
    -- Face holes participate in the Euler characteristic through loop counts.
    [
        testing.expect(
            [
                after.vertices + 2 * after.faces + before.edges + before.loops
                == before.vertices + 2 * before.faces + after.edges + after.loops
            ]
        )!
    ]
    -- Merge the result again; the source remains available throughout.
    merged ::= [
        t.merge_coplanar_faces(&split.model, .first = split.faces[0], .second = split.faces[1])!
    ]
    testing.expect(t.is_closed(&merged.model).ok)!
}
