-- Connect a face exterior to a hole with an internal bridge.
-- The bridge appears twice in the resulting walk, in opposite directions.
-- It connects loops without opening the closed shell or creating another face.
test usage_bridge_closed_face := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
    source ::= _closed_pocket(.allocator = allocator)!
    first_loop ::= t.face_loop(&source, .face = (.value = 0))!
    exterior ::= [t.loop_info(&source, .loop = first_loop)!].first
    index ::= first_loop | convert#(.to: UIntNative)(_)
    hole_loop ::= [index + 1] | convert#(.to: t.LoopId)(_)
    current ::= [t.loop_info(&source, .loop = hole_loop)!].first
    i :: UIntNative = 0
    while i < 3 {
        current = [t.halfedge_info(&source, .halfedge = current)!].next
        i = i + 1
    }
    operation ::= [
        t.bridge_planar_face(
            &source
            .face     = (.value = 0)
            .exterior = (.halfedge = exterior, .parameter = 0.5)
            .hole     = (.halfedge = current, .parameter = 0.5)
        )!
    ]
    counts ::= t.entity_counts(&operation.model)
    original ::= t.entity_counts(&source)
    testing.expect(t.is_closed(&operation.model).ok)!
    [
        testing.expect(
            [counts.vertices == original.vertices + 2 and counts.edges == original.edges + 3]
        )!
    ]
    testing.expect(counts.faces == original.faces and counts.loops + 1 == original.loops)!
    [
        testing.expect(
            [[t.face_info(&operation.model, .face = operation.face)!].loop_count == 1]
        )!
    ]
    edge ::= t.edge_info(&operation.model, .edge = operation.bridge_edge)!
    first ::= t.halfedge_info(&operation.model, .halfedge = edge.first)!
    match edge.second {
        ..none { [testing.fail()!] }
        ..some other {
            second ::= t.halfedge_info(&operation.model, .halfedge = other.value)!
            testing.expect(first.loop == second.loop and first.reversed != second.reversed)!
        }
    }
}
