_MergeLoop := (.first: UIntNative, .count: UIntNative, .outer: Bool)

implement ImplicitlyCopyable#(_MergeLoop) ()

-- Skip canceled interior uses by crossing into the other selected face. Bounds
-- on the walk turn a malformed cancellation cycle into an explicit rejection.
_merge_next := (.topology: &Topology, .removed: &DynamicArray#(Bool), .current: HalfEdgeId) -> (
    .result : Errable#(HalfEdgeId, MergeErrors)
) {
    current_item ::= _topology_halfedge_info(topology, .halfedge = current)!
    next ::= current_item.next
    limit ::= length(removed).count
    crossed :: UIntNative = 0
    while true {
        offset ::= next | convert#(.to: UIntNative)(_)
        if get(removed, .index = offset)! == false {
            result = ..ok next
            return
        }
        if crossed >= limit {
            result = ..error(.reason = ..invalid_merge_boundary)
            return
        }
        match _topology_opposite(topology, .halfedge = next)! {
            ..none {
                result = ..error(.reason = ..invalid_merge_boundary)
                return
            }
            ..some opposite {
                item ::= _topology_halfedge_info(topology, .halfedge = opposite.value)!
                next = item.next
            }
        }
        crossed = crossed + 1
    }
}

_MergeSelection := (
    .selected : DynamicArray#(Bool),
    .removed  : DynamicArray#(Bool)
)

_merge_selection := #(.Provider: Type: Allocator) (
    .topology: &Topology, .first: FaceId, .second: FaceId, .allocator: $&Provider
) -> (.result: Errable#(_MergeSelection, MergeErrors)) {
    count ::= _topology_entity_counts(topology).halfedges
    selected ::= DynamicArray#(Bool)(.allocator = allocator, .capacity = count)!
    removed ::= DynamicArray#(Bool)(.allocator = allocator, .capacity = count)!
    i :: UIntNative = 0
    while i < count {
        push($&selected, .value = false, .allocator = allocator)!
        push($&removed, .value = false, .allocator = allocator)!
        i = i + 1
    }
    which :: UIntNative = 0
    while which < 2 {
        face ::= first
        if which == 1 { face = second }
        item ::= _topology_face_info(topology, .face = face)!
        start ::= item.first_loop | convert#(.to: UIntNative)(_)
        loop :: UIntNative = 0
        while loop < item.loop_count {
            id ::= [start + loop] | convert#(.to: LoopId)(_)
            for entry in _topology_loop_halfedges(topology, .loop = id)! {
                offset ::= entry.id | convert#(.to: UIntNative)(_)
                slot ::= get_mutable_reference($&selected, .index = offset)!
                slot&= true
            }
            loop = loop + 1
        }
        which = which + 1
    }
    adjacent ::= false
    edge_count ::= _topology_entity_counts(topology).edges
    i = 0
    while i < edge_count {
        edge ::= get(&topology&._edges, .index = i)!
        match edge.second {
            ..none {}
            ..some opposite {
                a ::= edge.first | convert#(.to: UIntNative)(_)
                b ::= opposite.value | convert#(.to: UIntNative)(_)
                if get(&selected, .index = a)! and get(&selected, .index = b)! {
                    first_use ::= _topology_halfedge_info(topology, .halfedge = edge.first)!
                    second_use ::= _topology_halfedge_info(topology, .halfedge = opposite.value)!
                    -- The selected input faces are distinct. An edge joining two
                    -- loops of just one face is not an interface between them.
                    first_face ::= _topology_face_info(topology, .face = first)!
                    start ::= first_face.first_loop | convert#(.to: UIntNative)(_)
                    al ::= first_use.loop | convert#(.to: UIntNative)(_)
                    bl ::= second_use.loop | convert#(.to: UIntNative)(_)
                    in_a ::= al >= start and al - start < first_face.loop_count
                    in_b ::= bl >= start and bl - start < first_face.loop_count
                    if in_a != in_b {
                        slot_a ::= get_mutable_reference($&removed, .index = a)!
                        slot_a&= true
                        slot_b ::= get_mutable_reference($&removed, .index = b)!
                        slot_b&= true
                        adjacent = true
                    }
                }
            }
        }
        i = i + 1
    }
    if adjacent == false {
        result = ..error(.reason = ..not_adjacent)
        return
    }
    result = ..ok(.selected = ~selected, .removed = ~removed)
}

_merge_plane := #(.Scalar: Type: Float, .Provider: Type: Allocator) (
    .model: &Model#(Scalar), .first: FaceId, .second: FaceId, .allocator: $&Provider
) -> (.result: Errable#(g.Plane#(Scalar), MergeErrors)) {
    first_plane ::= face_plane(model, .face = first)!
    second_plane ::= face_plane(model, .face = second)!
    _merge_polygonal_boundary(.model = model, .face = first)!
    _merge_polygonal_boundary(.model = model, .face = second)!
    first_frame ::= g.frame(.origin = first_plane.origin, .axis = first_plane.normal)!
    second_frame ::= g.frame(.origin = second_plane.origin, .axis = second_plane.normal)!
    plane: g.Plane#(Scalar) = (.origin = first_frame.origin, .normal = first_frame.z)
    exterior ::= DynamicArray#(g.Point#(Scalar))(.allocator = allocator)!
    for entry in loop_halfedges(model, .loop = face_loop(model, .face = first)!)! {
        push(
            $&exterior
            .value     = point(model, .vertex = halfedge_vertex(entry.halfedge)!)!
            .allocator = allocator
        )!
    }
    exterior_view ::= view(&exterior)
    positive ::= g.contour_orientation(.points = exterior_view, .plane = plane)!
    if positive == false {
        plane.normal = (
            .x = 0.0 - plane.normal.x
            .y = 0.0 - plane.normal.y
            .z = [0.0 - plane.normal.z]
        )
    }
    which :: UIntNative = 0
    while which < 2 {
        selected ::= first
        other_origin ::= second_frame.origin
        other_normal ::= second_frame.z
        if which == 1 {
            selected = second
            other_origin = plane.origin
            other_normal = plane.normal
        }
        for boundary in face_loops(model, .face = selected)! {
            for entry in loop_halfedges(model, .loop = boundary.id)! {
                position ::= point(model, .vertex = halfedge_vertex(entry.halfedge)!)!
                distance ::= g.dot(
                    .left  = g.between(.from = other_origin, .to = position).result
                    .right = other_normal
                ).value
                if is_finite(distance).ok == false {
                    result = ..error(.reason = ..numeric_range)
                    return
                }
                if [
                    distance > model&._validation_tolerance
                    or distance < 0.0 - model&._validation_tolerance
                ] {
                    result = ..error(.reason = ..not_coplanar)
                    return
                }
            }
        }
        which = which + 1
    }
    second_exterior ::= DynamicArray#(g.Point#(Scalar))(.allocator = allocator)!
    for entry in loop_halfedges(model, .loop = face_loop(model, .face = second)!)! {
        push(
            $&second_exterior
            .value     = point(model, .vertex = halfedge_vertex(entry.halfedge)!)!
            .allocator = allocator
        )!
    }
    second_view ::= view(&second_exterior)
    if g.contour_orientation(.points = second_view, .plane = plane)! == false {
        result = ..error(.reason = ..inconsistent_orientation)
        return
    }
    result = ..ok plane
}

_merge_cycles := #(.Scalar: Type: Float, .Provider: Type: Allocator) (
    .model     : &Model#(Scalar),
    .selection : &_MergeSelection,
    .plane     : g.Plane#(Scalar),
    .allocator : $&Provider
) -> (.result: Errable#(DynamicArray#(_MergeLoop), MergeErrors)) {
    count ::= entity_counts(model).halfedges
    visited ::= DynamicArray#(Bool)(.allocator = allocator, .capacity = count)!
    cycles ::= DynamicArray#(_MergeLoop)(.allocator = allocator)!
    i :: UIntNative = 0
    while i < count {
        push($&visited, .value = false, .allocator = allocator)!
        i = i + 1
    }
    outer_count :: UIntNative = 0
    i = 0
    while i < count {
        if [
            get(&selection&.selected, .index = i)!
            and get(&selection&.removed, .index = i)! == false
            and get(&visited, .index = i)! == false
        ] {
            first ::= i | convert#(.to: HalfEdgeId)(_)
            current ::= first
            length :: UIntNative = 0
            points ::= DynamicArray#(g.Point#(Scalar))(.allocator = allocator)!
            while true {
                offset ::= current | convert#(.to: UIntNative)(_)
                if get(&visited, .index = offset)! or length >= count {
                    result = ..error(.reason = ..invalid_merge_boundary)
                    return
                }
                slot ::= get_mutable_reference($&visited, .index = offset)!
                slot&= true
                item ::= halfedge_info(model, .halfedge = current)!
                push(
                    $&points
                    .value     = point(model, .vertex = halfedge_vertex(item)!)!
                    .allocator = allocator
                )!
                length = length + 1
                current = _merge_next(
                    .topology = &model&._topology
                    .removed  = &selection&.removed
                    .current  = current
                )!
                if current == first { break }
            }
            points_view ::= view(&points)
            outer ::= g.contour_orientation(.points = points_view, .plane = plane)!
            if outer { outer_count = outer_count + 1 }
            cycle: _MergeLoop = (.first = i, .count = length, .outer = outer)
            push($&cycles, .value = cycle, .allocator = allocator)!
        }
        i = i + 1
    }
    if outer_count != 1 {
        result = ..error(.reason = ..invalid_merge_boundary)
        return
    }
    -- Place the unique exterior before the holes, without changing cycle winding.
    cycle_count ::= length(&cycles).count
    i = 0
    while i < cycle_count {
        candidate ::= get(&cycles, .index = i)!
        if candidate.outer and i != 0 {
            previous ::= get(&cycles, .index = 0)!
            first_slot ::= get_mutable_reference($&cycles, .index = 0)!
            first_slot&= candidate
            other_slot ::= get_mutable_reference($&cycles, .index = i)!
            other_slot&= previous
        }
        i = i + 1
    }
    uses ::= DynamicArray#(_BoundaryUse)(.allocator = allocator)!
    ranges ::= DynamicArray#(_BoundaryRange)(.allocator = allocator, .capacity = cycle_count)!
    i = 0
    while i < cycle_count {
        cycle ::= get(&cycles, .index = i)!
        start ::= length(&uses).count
        current ::= cycle.first | convert#(.to: HalfEdgeId)(_)
        j :: UIntNative = 0
        while j < cycle.count {
            item ::= halfedge_info(model, .halfedge = current)!
            use: _BoundaryUse = (
                .origin   = item.origin
                .edge     = item.edge
                .reversed = item.reversed
                .pcurve   = item.pcurve
            )
            push($&uses, .value = use, .allocator = allocator)!
            current = _merge_next(
                .topology = &model&._topology
                .removed  = &selection&.removed
                .current  = current
            )!
            j = j + 1
        }
        range: _BoundaryRange = (.start = start, .count = cycle.count)
        push($&ranges, .value = range, .allocator = allocator)!
        i = i + 1
    }
    contours ::= _boundary_contours(
        .uses       = &uses
        .ranges     = view(&ranges)
        .points     = &model&._points
        .edge_count = entity_counts(model).edges
        .allocator  = allocator
    )!
    _merge_validate_contours(
        .contours  = &contours
        .plane     = plane
        .tolerance = model&._validation_tolerance
        .allocator = allocator
    )!
    result = ..ok ~cycles
}

_merge_polygonal_boundary := #(.Scalar: Type: Float) (.model: &Model#(Scalar), .face: FaceId) -> (
    .result : Errable#(Void, MergeErrors)
) {
    if face_info(model, .face = face)!.loop_count == 0 {
        result = ..error(.reason = ..unsupported_boundary)
        return
    }
    for boundary in face_loops(model, .face = face)! {
        for entry in loop_halfedges(model, .loop = boundary.id)! {
            match entry.halfedge.origin {
                ..none {
                    result = ..error(.reason = ..unsupported_boundary)
                    return
                }
                ..some _ {}
            }
            edge ::= edge_info(model, .edge = entry.halfedge.edge)!
            match edge.curve {
                ..none {}
                ..some curve {
                    offset ::= curve.value | convert#(.to: UIntNative)(_)
                    descriptor ::= get(&model&._geometry.curves, .index = offset)!
                    if descriptor.kind != 0 {
                        result = ..error(.reason = ..unsupported_boundary)
                        return
                    }
                }
            }
        }
    }
    result = ..ok Void()
}
