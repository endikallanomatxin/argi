-- Temporary, resolved input. Publication keeps only the compact topology and
-- pooled geometry, not a second persistent edge endpoint representation.
_ResolvedTrim := #(.Scalar: Type: Float) (
    .edge        : EdgeId,
    .origin      : ?VertexId,
    .destination : ?VertexId,
    .curve       : CurveId,
    .interval    : CurveInterval#(Scalar),
    .pcurve      : PCurve#(Scalar),
    .reversed    : Bool
)

implement#(.Scalar: Type: Float) ImplicitlyCopyable#(_ResolvedTrim#(Scalar)) ()

_TrimFaceUses := #(.Scalar: Type: Float) (
    .uses         : &DynamicArray#(_ResolvedTrim#(Scalar)),
    .first_pcurve : UIntNative
)

implement#(.Scalar: Type: Float) _FaceUses#(_TrimFaceUses#(Scalar)) (
    .length = (.self: &_TrimFaceUses#(Scalar)) -> (.count: UIntNative) {
        count = length(self&.uses).count
    }
    .get = (.self: &_TrimFaceUses#(Scalar), .index: UIntNative) -> (
        .result : Errable#(_TopologyUse, (..out_of_bounds))
    ) {
        item ::= get(self&.uses, .index = index)!
        result = ..ok(
            .origin   = item.origin
            .edge     = item.edge
            .reversed = item.reversed
            .pcurve   = ..some(
                .value = [[[self&.first_pcurve + index] | convert#(.to: PCurveId)(_)]]
            )
        )
    }
)

-- Input is a borrowed flat use batch and contour lengths. The first planar
-- contour is exterior; the remaining contours are holes. Admission is separate
-- from the geometry-free writer and completes before any logical mutation.
declare_trimmed_face := #(.Scalar: Type: Float, .Provider: Type: Allocator) (
    .builder         : $&BrepBuilder#(Scalar),
    .surface         : idx.Index#(SurfaceId),
    .boundaries      : ArrayView#(TrimUse#(Scalar)),
    .contour_lengths : ArrayView#(UIntNative),
    .reversed        : Bool                    = false,
    .allocator       : $&Provider
) -> (.result: Errable#(idx.Index#(FaceId), BrepErrors)) {
    s ::= idx.resolve_index(.domain = &builder&._domain, .index = surface)!
    surface_id ::= s | convert#(.to: SurfaceId)(_)
    support ::= _pool_surface(&builder&._geometry, .surface = surface_id)!
    use_count ::= length(&boundaries).count
    loop_count ::= length(&contour_lengths).count
    if loop_count == 0 or use_count == 0 {
        result = ..error(.reason = ..invalid_region_lengths)
        return
    }
    total :: UIntNative = 0
    l :: UIntNative = 0
    while l < loop_count {
        n ::= get(&contour_lengths, .index = l)!
        if n == 0 or n > use_count - total {
            result = ..error(.reason = ..invalid_region_lengths)
            return
        }
        total = total + n
        l = l + 1
    }
    if total != use_count {
        result = ..error(.reason = ..invalid_region_lengths)
        return
    }
    edge_ids ::= DynamicArray#(UIntNative)(.allocator = allocator, .capacity = use_count)!
    halfedge_count ::= length(&builder&._halfedges).count
    uses ::= DynamicArray#(_ResolvedTrim#(Scalar))(
        .allocator = allocator, .capacity = use_count
    )!
    i :: UIntNative = 0
    while i < use_count {
        input ::= get(&boundaries, .index = i)!
        e ::= idx.resolve_index(.domain = &builder&._domain, .index = input.edge)!
        edge ::= get(&builder&._edges, .index = e)!
        push_assume_capacity($&edge_ids, .value = e)
        first ::= edge.first | convert#(.to: UIntNative)(_)
        if first < halfedge_count {
            match edge.second {
                ..some _ {
                    result = ..error(.reason = ..nonmanifold_edge)
                    return
                }
                ..none {}
            }
            old ::= get(&builder&._halfedges, .index = first)!
            if old.reversed == input.reversed {
                result = ..error(.reason = ..inconsistent_orientation)
                return
            }
        }
        origin :: ?VertexId = ..none
        destination :: ?VertexId = ..none
        match get(&builder&._edge_vertices, .index = e)! {
            ..none {}
            ..some endpoints {
                a ::= endpoints.value.start
                b ::= endpoints.value.end
                if input.reversed {
                    a = endpoints.value.end
                    b = endpoints.value.start
                }
                origin = ..some(
                    .value = [a | convert#(.to: VertexId)(_)]
                )
                destination = ..some(
                    .value = [b | convert#(.to: VertexId)(_)]
                )
            }
        }
        curve :: CurveId = (.value = 0)
        interval_id :: CurveIntervalId = (.value = 0)
        match edge.curve { ..none { abort } ..some value { curve = value.value } }
        match edge.interval { ..none { abort } ..some value { interval_id = value.value } }
        interval_index ::= interval_id | convert#(.to: UIntNative)(_)
        interval ::= get(&builder&._geometry.intervals, .index = interval_index)!
        item: _ResolvedTrim#(Scalar) = (
            .edge        = [e | convert#(.to: EdgeId)(_)]
            .origin      = origin
            .destination = destination
            .curve       = curve
            .interval    = interval
            .pcurve      = input.pcurve
            .reversed    = input.reversed
        )
        push_assume_capacity($&uses, .value = item)
        i = i + 1
    }
    order: _TrimEdgeOrder = ()
    sort(.self = $&edge_ids, .order = &order)
    i = 1
    while i < use_count {
        if get(&edge_ids, .index = i)! == get(&edge_ids, .index = i - 1)! {
            result = ..error(.reason = ..nonmanifold_edge)
            return
        }
        i = i + 1
    }
    _validate_trim_connectivity(.uses = &uses, .lengths = contour_lengths)!
    _admit_trimmed_region(
        .pools     = &builder&._geometry
        .support   = support
        .uses      = &uses
        .lengths   = contour_lengths
        .reversed  = reversed
        .tolerance = builder&._tolerance
        .allocator = allocator
    )!
    face_count ::= length(&builder&._faces).count
    loops ::= length(&builder&._loops).count
    pcurves ::= length(&builder&._geometry.pcurves).count
    maximum ::= integer_limits(.value = face_count).maximum
    if [
        use_count > maximum - halfedge_count
        or use_count > maximum - pcurves
        or loop_count > maximum - loops
        or face_count == maximum
    ] {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    ensure_capacity(
        .self      = $&builder&._halfedges
        .capacity  = halfedge_count + use_count
        .allocator = allocator
    )!
    ensure_capacity(
        .self = $&builder&._loops, .capacity = loops + loop_count, .allocator = allocator
    )!
    ensure_capacity(
        .self = $&builder&._faces, .capacity = face_count + 1, .allocator = allocator
    )!
    ensure_capacity(
        .self = $&builder&._face_surfaces, .capacity = face_count + 1, .allocator = allocator
    )!
    ensure_capacity(
        .self      = $&builder&._geometry.pcurves
        .capacity  = pcurves + use_count
        .allocator = allocator
    )!
    i = 0
    while i < use_count {
        item ::= get(&uses, .index = i)!
        push_assume_capacity($&builder&._geometry.pcurves, .value = item.pcurve)
        i = i + 1
    }
    source: _TrimFaceUses#(Scalar) = (.uses = &uses, .first_pcurve = pcurves)
    _append_topology_face_assume_capacity(
        .halfedges    = $&builder&._halfedges
        .loops        = $&builder&._loops
        .faces        = $&builder&._faces
        .uses         = &source
        .loop_lengths = contour_lengths
        .reversed     = reversed
    )
    push_assume_capacity($&builder&._face_surfaces, .value = surface_id)
    _attach_trim_uses(.edges = $&builder&._edges, .uses = &uses, .first = halfedge_count)!
    result = ..ok idx.bind_index#(FaceId)(
        .domain = &builder&._domain, .offset = face_count
    ).value
}

_validate_trim_connectivity := #(.Scalar: Type: Float) (
    .uses: &DynamicArray#(_ResolvedTrim#(Scalar)), .lengths: ArrayView#(UIntNative)
) -> (.result: Errable#(Void, BrepErrors)) {
    l :: UIntNative = 0
    start :: UIntNative = 0
    while l < length(&lengths).count {
        n ::= get(&lengths, .index = l)!
        i :: UIntNative = 0
        while i < n {
            a ::= get(uses, .index = start + i)!
            b ::= get(uses, .index = start + [i + 1] % n)!
            match a.destination {
                ..none {
                    if n != 1 {
                        result = ..error(.reason = ..invalid_region_lengths)
                        return
                    }
                }
                ..some end {
                    match b.origin {
                        ..none {
                            result = ..error(.reason = ..inconsistent_orientation)
                            return
                        }
                        ..some begin {
                            if end.value != begin.value {
                                result = ..error(.reason = ..inconsistent_orientation)
                                return
                            }
                        }
                    }
                }
            }
            i = i + 1
        }
        start = start + n
        l = l + 1
    }
    result = ..ok Void()
}

_attach_trim_uses := #(.Scalar: Type: Float) (
    .edges : $&DynamicArray#(Edge),
    .uses  : &DynamicArray#(_ResolvedTrim#(Scalar)),
    .first : UIntNative
) -> (.result: Errable#(Void, BrepErrors)) {
    i :: UIntNative = 0
    while i < length(uses).count {
        item ::= get(uses, .index = i)!
        e ::= item.edge | convert#(.to: UIntNative)(_)
        edge ::= get(edges, .index = e)!
        previous ::= edge.first | convert#(.to: UIntNative)(_)
        id ::= [first + i] | convert#(.to: HalfEdgeId)(_)
        _attach_brep_use(
            .edges = edges, .index = e, .halfedge = id, .first = [previous >= first]
        )!
        i = i + 1
    }
    result = ..ok Void()
}

_TrimEdgeOrder: Type = ()

implement OrderPolicy#(_TrimEdgeOrder, UIntNative) (
    .less = (.self: &_TrimEdgeOrder, .left: &UIntNative, .right: &UIntNative) -> (.ok: Bool) {
        ok = left&< right&
    }
)
