-- Edge manifoldness is insufficient: all outgoing halfedges at a vertex must
-- form one cycle (interior) or one chain (boundary), never disconnected fans.
_validate_vertices := (
    .topology: &Topology, .allocator: $&Virtual#(Allocator)
) -> (.result: Errable#(Void, BuildErrors)) {

    vertex_count ::= topology&._vertex_count
    halfedge_count ::= length(&topology&._halfedges).count
    predecessors ::= _topology_predecessors(.topology = topology, .allocator = allocator)!
    starts ::= DynamicArray#(UIntNative)(.allocator = allocator, .capacity = vertex_count)!
    valences ::= DynamicArray#(UIntNative)(.allocator = allocator, .capacity = vertex_count)!
    i :: UIntNative = 0
    while i < vertex_count {
        push($&starts, .value = halfedge_count, .allocator = allocator)!
        push($&valences, .value = 0, .allocator = allocator)!
        i = i + 1
    }
    i = 0
    while i < halfedge_count {
        halfedge ::= _topology_halfedge_info(
            topology, .halfedge = [i | convert#(.to: HalfEdgeId)(_)]
        )!
        match halfedge.origin {
            ..none {
                i = i + 1
                continue
            }
            ..some _ {}
        }
        vertex ::= [
            [
                unwrap_or_abort(.value = halfedge_vertex(halfedge)).result
                | convert#(.to: UIntNative)(_)
            ]
        ]
        valence ::= get_mutable_reference($&valences, .index = vertex)!
        valence&= valence&+ 1
        start ::= get_mutable_reference($&starts, .index = vertex)!
        if start&== halfedge_count { start&= i }
        previous ::= get(&predecessors, .index = i)!
        match _topology_opposite(
            topology, .halfedge = [previous | convert#(.to: HalfEdgeId)(_)]
        )! {
            ..none { start&= i }
            ..some _ {}
        }
        i = i + 1
    }
    i = 0
    while i < vertex_count {
        expected ::= get(&valences, .index = i)!
        if expected == 0 {
            result = ..error(.reason = ..unused_vertex)
            return
        }
        start ::= get(&starts, .index = i)!
        current ::= start
        visited :: UIntNative = 0
        while true {
            visited = visited + 1
            if visited > expected {
                result = ..error(.reason = ..nonmanifold_vertex)
                return
            }
            match _topology_opposite(
                topology, .halfedge = [current | convert#(.to: HalfEdgeId)(_)]
            )! {
                ..none { break }
                ..some paired {
                    other ::= _topology_halfedge_info(topology, .halfedge = paired.value)!
                    current = [other.next | convert#(.to: UIntNative)(_)]
                }
            }
            if current == start { break }
        }
        if visited != expected {
            result = ..error(.reason = ..nonmanifold_vertex)
            return
        }
        i = i + 1
    }
    result = ..ok Void()
}
