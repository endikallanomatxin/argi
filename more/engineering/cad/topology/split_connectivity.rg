-- Rebuild incidence by edge ID, without sorting endpoint pairs or welding.
_split_pair_edges := #(.Scalar: Type: Float, .Provider: Type: Allocator) (
    .model      : &Model#(Scalar),
    .halfedges  : &DynamicArray#(HalfEdge),
    .first      : _SplitEndpoint#(Scalar),
    .second     : _SplitEndpoint#(Scalar),
    .edge_count : UIntNative,
    .allocator  : $&Provider
) -> (.result: Errable#(DynamicArray#(Edge), SplitErrors)) {
    count ::= length(halfedges).count
    sentinel ::= count | convert#(.to: HalfEdgeId)(_)
    old_count ::= entity_counts(model).edges
    edges ::= DynamicArray#(Edge)(.allocator = allocator, .capacity = edge_count)!
    i :: UIntNative = 0
    while i < edge_count {
        curve :: ?CurveId = ..none
        interval :: ?CurveIntervalId = ..none
        if i < old_count {
            id ::= i | convert#(.to: EdgeId)(_)
            curve = edge_info(model, .edge = id)!.curve
            interval = edge_info(model, .edge = id)!.interval
            if [first.insert and id == first.edge] or [second.insert and id == second.edge] {
                curve = ..none
                interval = ..none
            }
        }
        item: Edge = (
            .first    = sentinel
            .second   = ..none
            .curve    = curve
            .interval = interval
        )
        push($&edges, .value = item, .allocator = allocator)!
        i = i + 1
    }
    i = 0
    while i < count {
        use ::= get(halfedges, .index = i)!
        edge_index ::= use.edge | convert#(.to: UIntNative)(_)
        edge ::= get_mutable_reference($&edges, .index = edge_index)!
        id ::= i | convert#(.to: HalfEdgeId)(_)
        if edge&.first == sentinel {
            edge&.first = id
        } else {
            match edge&.second {
                ..some _ {
                    result = ..error(.reason = ..nonmanifold_edge)
                    return
                }
                ..none {}
            }
            index ::= edge&.first | convert#(.to: UIntNative)(_)
            other ::= get(halfedges, .index = index)!
            if other.reversed == use.reversed {
                result = ..error(.reason = ..inconsistent_orientation)
                return
            }
            paired: ?HalfEdgeId = ..some(.value = id)
            edge&.second = paired
        }
        i = i + 1
    }
    i = 0
    while i < edge_count {
        if get(&edges, .index = i)!.first == sentinel {
            result = ..error(.reason = ..unused_edge)
            return
        }
        i = i + 1
    }
    result = ..ok ~edges
}
