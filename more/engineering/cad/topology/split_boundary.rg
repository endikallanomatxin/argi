-- Parameters follow the selected halfedge, rather than the canonical edge.
BoundaryPoint := #(.Scalar: Type: Float) (.halfedge: HalfEdgeId, .parameter: Scalar)

implement#(.Scalar: Type: Float) ImplicitlyCopyable#(BoundaryPoint#(Scalar)) ()

_SplitEndpoint := #(.Scalar: Type: Float) (
    .halfedge : HalfEdgeId,
    .vertex   : VertexId,
    .insert   : Bool,
    .edge     : EdgeId,
    .point    : g.Point#(Scalar)
)

implement#(.Scalar: Type: Float) ImplicitlyCopyable#(_SplitEndpoint#(Scalar)) ()

_split_endpoint := #(.Scalar: Type: Float) (
    .model      : &Model#(Scalar),
    .loop       : LoopId,
    .location   : BoundaryPoint#(Scalar),
    .new_vertex : VertexId
) -> (.result: Errable#(_SplitEndpoint#(Scalar), SplitErrors)) {
    if [
        is_finite(location.parameter).ok == false
        or location.parameter < 0.0
        or location.parameter > 1.0
    ] {
        result = ..error(.reason = ..invalid_parameter)
        return
    }
    id ::= location.halfedge
    item ::= halfedge_info(model, .halfedge = id)!
    if item.loop != loop {
        result = ..error(.reason = ..endpoint_not_on_boundary)
        return
    }
    parameter ::= location.parameter
    if parameter == 1.0 {
        id = item.next
        item = halfedge_info(model, .halfedge = id)!
        parameter = 0.0
    }
    origin ::= halfedge_vertex(item)!
    position ::= point(model, .vertex = origin)!
    vertex ::= origin
    insert ::= parameter != 0.0
    if insert {
        position = halfedge_point(model, .halfedge = id, .parameter = parameter)!
        next ::= halfedge_info(model, .halfedge = item.next)!
        end ::= point(model, .vertex = halfedge_vertex(next)!)!
        start ::= point(model, .vertex = origin)!
        left ::= g.norm(.vector = g.between(.from = start, .to = position).result).value
        right ::= g.norm(.vector = g.between(.from = position, .to = end).result).value
        if is_finite(left).ok == false or is_finite(right).ok == false {
            result = ..error(.reason = ..numeric_range)
            return
        }
        if left <= model&._validation_tolerance or right <= model&._validation_tolerance {
            result = ..error(.reason = ..degenerate_cut)
            return
        }
        vertex = new_vertex
    }
    result = ..ok(
        .halfedge = id
        .vertex   = vertex
        .insert   = insert
        .edge     = item.edge
        .point    = position
    )
}

_SplitBoundary := (
    .uses   : DynamicArray#(_BoundaryUse),
    .loops  : DynamicArray#(_BoundaryRange),
    .first  : UIntNative,
    .second : UIntNative
)

-- Expand both uses of a split edge. Old edge IDs keep the first canonical
-- segment; appended IDs identify the second segment, independently of winding.
_split_refine := #(.Scalar: Type: Float) (
    .model     : &Model#(Scalar),
    .first     : _SplitEndpoint#(Scalar),
    .second    : _SplitEndpoint#(Scalar),
    .parts     : [2]EdgeId,
    .allocator : $&Virtual#(Allocator)
) -> (.result: Errable#(_SplitBoundary, SplitErrors)) {

    counts ::= entity_counts(model)
    uses ::= DynamicArray#(_BoundaryUse)(
        .allocator = allocator, .capacity = [counts.halfedges + 4]
    )!
    loops ::= DynamicArray#(_BoundaryRange)(.allocator = allocator, .capacity = counts.loops)!
    first_position :: UIntNative = 0
    second_position :: UIntNative = 0
    l :: UIntNative = 0
    while l < counts.loops {
        loop ::= l | convert#(.to: LoopId)(_)
        start ::= length(&uses).count
        for entry in loop_halfedges(model, .loop = loop)! {
            item ::= entry.halfedge
            a :: _BoundaryUse = (
                .origin   = item.origin
                .edge     = item.edge
                .reversed = item.reversed
                .pcurve   = item.pcurve
            )
            b :: _BoundaryUse = a
            insert ::= false
            if entry.id == first.halfedge {
                first_position = [length(&uses).count - start]
                if first.insert { first_position = first_position + 1 }
            }
            if entry.id == second.halfedge {
                second_position = [length(&uses).count - start]
                if second.insert { second_position = second_position + 1 }
            }
            endpoint ::= first
            part ::= parts[0]
            if second.insert and item.edge == second.edge {
                endpoint = second
                part = parts[1]
            }
            if endpoint.insert and item.edge == endpoint.edge {
                insert = true
                b = (
                    .origin   = ..some(.value = endpoint.vertex)
                    .edge     = item.edge
                    .reversed = item.reversed
                    .pcurve   = item.pcurve
                )
                if item.reversed {
                    a = (
                        .origin   = item.origin
                        .edge     = part
                        .reversed = item.reversed
                        .pcurve   = item.pcurve
                    )
                } else {
                    b = (
                        .origin   = ..some(.value = endpoint.vertex)
                        .edge     = part
                        .reversed = item.reversed
                        .pcurve   = item.pcurve
                    )
                }
            }
            push($&uses, .value = a, .allocator = allocator)!
            if insert { push($&uses, .value = b, .allocator = allocator)! }
        }
        range: _BoundaryRange = (
            .start = start
            .count = [length(&uses).count - start]
        )
        push($&loops, .value = range, .allocator = allocator)!
        l = l + 1
    }
    result = ..ok(
        .uses   = ~uses
        .loops  = ~loops
        .first  = first_position
        .second = second_position
    )
}

-- A cut closes a contiguous part of the topological walk. Extract geometry
-- after adding the chord; bridges shared by both output faces remain boundaries.
_split_candidate_region := #(.Scalar: Type: Float) (
    .uses       : &DynamicArray#(_BoundaryUse),
    .range      : _BoundaryRange,
    .offset     : UIntNative,
    .count      : UIntNative,
    .chord      : _BoundaryUse,
    .edge_count : UIntNative,
    .points     : &DynamicArray#(g.Point#(Scalar)),
    .plane      : g.Plane#(Scalar),
    .positive   : Bool,
    .tolerance  : Scalar,
    .allocator  : $&Virtual#(Allocator)
) -> (.result: Errable#(_PlanarContours#(Scalar), SplitErrors)) {

    if count < 3 {
        result = ..error(.reason = ..degenerate_cut)
        return
    }
    selected ::= DynamicArray#(_BoundaryUse)(.allocator = allocator, .capacity = count)!
    cursor ::= offset
    i :: UIntNative = 0
    while i < count - 1 {
        push(
            $&selected
            .value     = get(uses, .index = range.start + cursor)!
            .allocator = allocator
        )!
        cursor = [cursor + 1] % range.count
        i = i + 1
    }
    push($&selected, .value = chord, .allocator = allocator)!
    selected_range: _BoundaryRange = (.start = 0, .count = count)
    region ::= _walk_region(
        .uses       = &selected
        .range      = selected_range
        .points     = points
        .edge_count = edge_count
        .plane      = plane
        .positive   = positive
        .tolerance  = tolerance
        .allocator  = allocator
    )!
    result = ..ok ~region
}

-- Editing accepts polygonal boundary walks, including paired bridge uses.
_require_linear_planar_boundaries := #(.Scalar: Type: Float) (
    .model: &Model#(Scalar), .face: FaceId
) -> (.result: Errable#(Void, SplitErrors)) {
    info ::= _topology_face_info(&model&._topology, .face = face)!
    first ::= info.first_loop | convert#(.to: UIntNative)(_)
    component_index :: UIntNative = 0
    while component_index < info.loop_count {
        loop_id ::= [first + component_index] | convert#(.to: LoopId)(_)
        component ::= _topology_loop_info(&model&._topology, .loop = loop_id)!
        current ::= component.first
        visited :: UIntNative = 0
        while visited < component.count {
            halfedge ::= _topology_halfedge_info(&model&._topology, .halfedge = current)!
            match halfedge.pcurve {
                ..some _ {
                    result = ..error(.reason = ..unsupported_boundary)
                    return
                }
                ..none {}
            }
            halfedge_vertex(halfedge)!
            match edge_curve(model, .edge = halfedge.edge)! {
                ..ellipse _ {
                    result = ..error(.reason = ..unsupported_boundary)
                    return
                }
                ..segment _ {}
                ..circle _ {
                    result = ..error(.reason = ..unsupported_boundary)
                    return
                }
            }
            current = halfedge.next
            visited = visited + 1
        }
        component_index = component_index + 1
    }
    result = ..ok Void()
}
