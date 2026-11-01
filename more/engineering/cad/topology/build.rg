BuildErrors := (
    ..invalid_tolerance,
    ..invalid_coordinate,
    ..degenerate_face,
    ..nonplanar_face,
    ..nonconvex_face,
    ..numeric_range,
    ..numerical_ambiguity,
    ..out_of_bounds,
    ..invalid_face_lengths,
    ..repeated_vertex,
    ..inconsistent_orientation,
    ..nonmanifold_edge,
    ..nonmanifold_vertex,
    ..unused_vertex,
    ..open_boundary,
    ..invalid_region_lengths,
    ..intersecting_contours,
    ..invalid_region_nesting,
    ..out_of_memory,
    ..invalid_surface,
    ..wrong_domain,
    ..unused_edge
)

_Candidate := (.low: UIntNative, .high: UIntNative, .halfedge: UIntNative)

implement ImplicitlyCopyable#(_Candidate) ()

_ByEndpoints: Type = ()

implement OrderPolicy#(_ByEndpoints, _Candidate) (
    .less = (.self: &_ByEndpoints, .left: &_Candidate, .right: &_Candidate) -> (.ok: Bool) {
        ok = left&.low < right&.low or [left&.low == right&.low and left&.high < right&.high]
    }
)

-- Shared construction reads borrowed index and length sources directly.
_build_faces := #(
    .Scalar    : Type: Float,
    .Indices   : Type: IndexableValue#(.Item: UIntNative),
    .Lengths   : Type: IndexableValue#(.Item: UIntNative),
    .FaceLoops : Type: IndexableValue#(.Item: UIntNative)
) (
    .points           : ArrayView#(g.Point#(Scalar)),
    .indices          : &Indices,
    .face_lengths     : &Lengths,
    .face_loop_counts : &FaceLoops,
    .planar_regions   : Bool,
    .supplied_planes  : &DynamicArray#(g.Plane#(Scalar)),
    .tolerance        : Scalar,
    .allocator        : $&Virtual#(Allocator),
    .require_closed   : Bool        = false
) -> (.result: Errable#(Model#(Scalar), BuildErrors)) {

    if is_finite(tolerance).ok == false or tolerance <= 0.0 {
        result = ..error(.reason = ..invalid_tolerance)
        return
    }
    vertex_count ::= length(&points).count
    halfedge_count ::= length(indices).count
    loop_count ::= length(face_lengths).count
    face_count ::= length(face_loop_counts).count
    if face_count == 0 or halfedge_count == 0 {
        result = ..error(.reason = ..invalid_face_lengths)
        return
    }
    f :: UIntNative = 0
    cursor :: UIntNative = 0
    while f < loop_count {
        count ::= get(face_lengths, .index = f)!
        if count < 3 {
            result = ..error(.reason = ..degenerate_face)
            return
        }
        if count > halfedge_count - cursor {
            result = ..error(.reason = ..invalid_face_lengths)
            return
        }
        cursor = cursor + count
        f = f + 1
    }
    if cursor != halfedge_count {
        result = ..error(.reason = ..invalid_face_lengths)
        return
    }
    f = 0
    cursor = 0
    while f < face_count {
        n ::= get(face_loop_counts, .index = f)!
        if n == 0 or n > loop_count - cursor {
            result = ..error(.reason = ..invalid_region_lengths)
            return
        }
        cursor = cursor + n
        f = f + 1
    }
    if cursor != loop_count {
        result = ..error(.reason = ..invalid_region_lengths)
        return
    }
    i :: UIntNative = 0

    while i < vertex_count {
        if g.finite_point(get(&points, .index = i)!).ok == false {
            result = ..error(.reason = ..invalid_coordinate)
            return
        }
        i = i + 1
    }
    i = 0
    while i < halfedge_count {
        if get(indices, .index = i)! >= vertex_count {
            result = ..error(.reason = ..out_of_bounds)
            return
        }
        i = i + 1
    }
    owned_points ::= DynamicArray#(g.Point#(Scalar))(
        .allocator = allocator, .capacity = vertex_count
    )!
    edges ::= DynamicArray#(Edge)(.allocator = allocator, .capacity = halfedge_count)!
    halfedges ::= DynamicArray#(HalfEdge)(.allocator = allocator, .capacity = halfedge_count)!
    loops ::= DynamicArray#(Loop)(.allocator = allocator, .capacity = loop_count)!
    faces ::= DynamicArray#(Face)(.allocator = allocator, .capacity = face_count)!
    pools ::= _GeometryPools#(Scalar)(.allocator = allocator)!
    planes ::= DynamicArray#(SurfaceId)(.allocator = allocator, .capacity = face_count)!
    candidates ::= DynamicArray#(_Candidate)(.allocator = allocator, .capacity = halfedge_count)!
    -- Per-vertex marks avoid quadratic duplicate checks in large polygons.
    seen ::= DynamicArray#(UIntNative)(.allocator = allocator, .capacity = vertex_count)!
    i = 0
    while i < vertex_count {
        push($&owned_points, .value = get(&points, .index = i)!, .allocator = allocator)!
        push($&seen, .value = face_count, .allocator = allocator)!
        i = i + 1
    }
    f = 0
    cursor = 0
    loop_index :: UIntNative = 0
    first_loop :: UIntNative = 0
    face_loops ::= get(face_loop_counts, .index = f)!
    while loop_index < loop_count {
        start ::= cursor

        end ::= start + get(face_lengths, .index = loop_index)!
        cursor = end
        i = start
        while i < end {
            origin ::= get(indices, .index = i)!
            mark ::= get_mutable_reference($&seen, .index = origin)!
            if mark&== f {
                result = ..error(.reason = ..repeated_vertex)
                return
            }
            mark&= f
            next ::= i + 1
            if next == end { next = start }
            target ::= get(indices, .index = next)!
            low ::= origin
            high ::= target
            if low > high {
                low = target
                high = origin
            }
            push(
                $&candidates
                .value     = (.low = low, .high = high, .halfedge = i)
                .allocator = allocator
            )!
            origin_id: VertexId = [origin | convert#(.to: VertexId)(_)]
            item: HalfEdge = (
                .origin = ..some(.value = origin_id)
                .edge   = (.value = 0)
                .next   = [next | convert#(.to: HalfEdgeId)(_)]
                .loop   = [loop_index | convert#(.to: LoopId)(_)]
            )
            push($&halfedges, .value = item, .allocator = allocator)!
            i = i + 1
        }
        if planar_regions == false {
            plane ::= g.polygon_plane#(Scalar)(
                .points    = points
                .indices   = indices
                .start     = start
                .count     = end - start
                .tolerance = tolerance
            )!
            surface: g.Surface#(Scalar) = ..plane(.value = plane)
            id ::= _pool_add_surface(
                .pools = $&pools, .surface = surface, .allocator = allocator
            )!
            push($&planes, .value = id, .allocator = allocator)!
        }
        push(
            $&loops
            .value = (
                .first = [start | convert#(.to: HalfEdgeId)(_)], .count = [end - start]
            )
            .allocator = allocator
        )!
        loop_index = loop_index + 1
        if loop_index == first_loop + face_loops {
            if planar_regions {
                surface: g.Surface#(Scalar) = ..plane(
                    .value = get(supplied_planes, .index = f)!
                )
                id ::= _pool_add_surface(
                    .pools = $&pools, .surface = surface, .allocator = allocator
                )!
                push($&planes, .value = id, .allocator = allocator)!
            }
            push(
                $&faces
                .value = (
                    .first_loop = [first_loop | convert#(.to: LoopId)(_)]
                    .loop_count = face_loops
                    .genus      = 0
                )
                .allocator = allocator
            )!
            f = f + 1
            first_loop = loop_index
            if f < face_count { face_loops = get(face_loop_counts, .index = f)! }
        }
    }
    order ::= _ByEndpoints()
    sort(.self = $&candidates, .order = &order)
    closed ::= true
    i = 0
    while i < halfedge_count {
        first ::= get(&candidates, .index = i)!
        end ::= i + 1
        while end < halfedge_count {
            candidate ::= get(&candidates, .index = end)!
            if candidate.low != first.low or candidate.high != first.high { break }
            end = end + 1
        }
        if end - i > 2 {
            result = ..error(.reason = ..nonmanifold_edge)
            return
        }
        second :: ?HalfEdgeId = ..none
        if end - i == 2 {
            other ::= get(&candidates, .index = i + 1)!
            first_halfedge ::= get(&halfedges, .index = first.halfedge)!
            other_halfedge ::= get(&halfedges, .index = other.halfedge)!
            if [
                unwrap_or_abort(.value = halfedge_vertex(first_halfedge)).result
                == unwrap_or_abort(.value = halfedge_vertex(other_halfedge)).result
            ] {
                result = ..error(.reason = ..inconsistent_orientation)
                return
            }
            second = ..some(
                .value = [other.halfedge | convert#(.to: HalfEdgeId)(_)]
            )
        } else {
            closed = false
        }
        edge_index ::= length(&edges).count
        item: Edge = (
            .first  = [first.halfedge | convert#(.to: HalfEdgeId)(_)]
            .second = second
            .curve  = ..none
        )
        push($&edges, .value = item, .allocator = allocator)!
        while i < end {
            candidate ::= get(&candidates, .index = i)!
            item ::= get_mutable_reference($&halfedges, .index = candidate.halfedge)!
            item&.reversed = candidate.halfedge != first.halfedge
            item&.edge = [edge_index | convert#(.to: EdgeId)(_)]
            i = i + 1
        }
    }
    connectivity: Topology = (
        ._vertex_count = vertex_count
        ._edges        = ~edges
        ._halfedges    = ~halfedges
        ._loops        = ~loops
        ._faces        = ~faces
        ._closed       = closed
    )
    _validate_vertices(&connectivity, .allocator = allocator)!
    if require_closed and closed == false {
        result = ..error(.reason = ..open_boundary)
        return
    }
    domain ::= idx.IndexDomain(.allocator = allocator)!
    result = ..ok(
        ._domain               = ~domain
        ._topology             = ~connectivity
        ._points               = ~owned_points
        ._geometry             = ~pools
        ._face_surfaces        = ~planes
        ._validation_tolerance = tolerance
    )
}
