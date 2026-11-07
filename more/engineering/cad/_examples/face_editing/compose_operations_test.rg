-- Advanced: compose bridge, split and merge on the same closed model.
-- Find endpoints in the current result instead of reusing obsolete halfedge IDs.
-- The final checks show how correspondences preserve the internal bridge.
test usage_bridge_split_merge_closed_face := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    source ::= _closed_pocket(.allocator = allocator)!
    operation ::= [
        t.bridge_planar_face(
            &source
            .face     = (.value = 0)
            .exterior = (.halfedge = (.value = 0), .parameter = 0.0)
            .hole     = (.halfedge = (.value = 4), .parameter = 0.0)
        )!
    ]
    endpoints ::= _cut_endpoints(&operation.model, operation.bridge_edge)!
    cut ::= [
        t.split_planar_face(
            &operation.model
            .face  = (.value = 0)
            .start = (.halfedge = endpoints.bottom, .parameter = 0.875)
            .end   = (.halfedge = endpoints.top, .parameter = 0.125)
        )!
    ]
    before ::= t.entity_counts(&operation.model)
    after ::= t.entity_counts(&cut.model)
    testing.expect(t.is_closed(&cut.model).ok)!
    testing.expect(after.vertices == before.vertices + 2 and after.edges == before.edges + 3)!
    testing.expect(after.faces == before.faces + 1 and after.loops == before.loops + 1)!
    [
        testing.expect(
            [
                after.vertices + after.faces + before.edges
                == before.vertices + before.faces + after.edges
            ]
        )!
    ]
    testing.expect(t.entity_counts(&source).faces == before.faces)!
    -- Merge the split faces, then follow the bridge through the correspondence.
    merged ::= [
        t.merge_coplanar_faces(&cut.model, .first = cut.faces[0], .second = cut.faces[1])!
    ]
    restored ::= t.entity_counts(&merged.model)
    testing.expect(t.is_closed(&merged.model).ok)!
    [
        testing.expect(
            [restored.vertices == before.vertices + 2 and restored.edges == before.edges + 2]
        )!
    ]
    testing.expect(restored.faces == before.faces and restored.loops == before.loops)!
    [
        testing.expect(
            [
                restored.vertices + restored.faces + before.edges
                == before.vertices + before.faces + restored.edges
            ]
        )!
    ]
    match [t.mapped_edge(&merged, .source_edge = operation.bridge_edge)!] {
        ..none { [testing.fail()!] }
        ..some image {
            edge ::= t.edge_info(&merged.model, .edge = image.value)!
            match edge.second {
                ..none { [testing.fail()!] }
                ..some other {
                    a ::= t.halfedge_info(&merged.model, .halfedge = edge.first)!
                    b ::= t.halfedge_info(&merged.model, .halfedge = other.value)!
                    testing.expect(a.loop == b.loop and a.reversed != b.reversed)!
                }
            }
        }
    }
}

_CutEndpoints := (.bottom: t.HalfEdgeId, .top: t.HalfEdgeId)

-- Locate current edges by vertex identity. Queries are plain fallible
-- operations; the caller adds context once for this lookup as a whole.
_cut_endpoints := (.model: &t.Model#(Float64), .bridge_edge: t.EdgeId) -> !_CutEndpoints {
    bottom :: t.HalfEdgeId = (.value = 0)
    top :: t.HalfEdgeId = (.value = 0)
    for entry in t.loop_halfedges(model, .loop = t.face_loop(model, .face = (.value = 0))!)! {
        origin ::= t.halfedge_vertex(entry.halfedge)!
        if origin.value == 0 and entry.halfedge.edge != bridge_edge { bottom = entry.id }
        if origin.value == 2 { top = entry.id }
    }
    result = ..ok(.bottom = bottom, .top = top)
}
