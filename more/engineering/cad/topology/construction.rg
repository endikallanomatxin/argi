-- Geometry-free connectivity construction. Borrowed sources let batch polygon
-- input and explicit analytic uses share this writer without flattening buffers.
_TopologyUse := (
    .origin   : ?VertexId,
    .edge     : EdgeId,
    .reversed : Bool,
    .pcurve   : ?PCurveId  = ..none
)

implement ImplicitlyCopyable#(_TopologyUse) ()

_FaceUses#(.Collection: Type): Contract = (
    .length : (.self: &Collection) -> (.count: UIntNative)
    .get    : (.self: &Collection, .index: UIntNative) -> (
        .result : Errable#(_TopologyUse, (..out_of_bounds))
    )
)

implement _FaceUses#(ArrayView#(_TopologyUse)) (
    .length = (.self: &ArrayView#(_TopologyUse)) -> (.count: UIntNative) {
        count = Indexable#(ArrayView#(_TopologyUse)).length(self).count
    }
    .get = (.self: &ArrayView#(_TopologyUse), .index: UIntNative) -> (
        .result : Errable#(_TopologyUse, (..out_of_bounds))
    ) {
        result = IndexableValue#(ArrayView#(_TopologyUse)).get(self, .index = index)
    }
)

_BuilderFaceUses := (
    .edges : &DynamicArray#(_BuilderEdge),
    .uses  : &DynamicArray#(_BuilderUse),
    .start : UIntNative,
    .count : UIntNative
)

implement _FaceUses#(_BuilderFaceUses) (
    .length = (.self: &_BuilderFaceUses) -> (.count: UIntNative) { count = self&.count }
    .get    = (.self: &_BuilderFaceUses, .index: UIntNative) -> (
        .result : Errable#(_TopologyUse, (..out_of_bounds))
    ) {
        if index >= self&.count {
            result = ..error(.reason = ..out_of_bounds)
            return
        }
        use ::= get(self&.uses, .index = self&.start + index)!
        edge ::= get(self&.edges, .index = use.edge)!
        origin ::= edge.start
        if use.reversed { origin = edge.end }
        result = ..ok(
            .origin   = ..some(.value = [origin | convert#(.to: VertexId)(_)])
            .edge     = [use.edge | convert#(.to: EdgeId)(_)]
            .reversed = use.reversed
        )
    }
)

-- Caller has admitted geometry, checked source bounds/loop lengths and reserved
-- capacity for all records. This infallible commit performs no allocation and
-- knows nothing about planes, circles, pcurves or numerical tolerances.
_append_topology_face_assume_capacity := #(.Uses: Type: _FaceUses) (
    .halfedges    : $&DynamicArray#(HalfEdge),
    .loops        : $&DynamicArray#(Loop),
    .faces        : $&DynamicArray#(Face),
    .uses         : &Uses,
    .loop_lengths : ArrayView#(UIntNative),
    .reversed     : Bool,
    .genus        : UIntNative                 = 0
) -> (.face: FaceId) {
    loop_start ::= length(loops).count
    face_index ::= length(faces).count
    loop_count ::= length(&loop_lengths).count
    cursor :: UIntNative = 0
    l :: UIntNative = 0
    while l < loop_count {
        count ::= unwrap_or_abort(.value = get(&loop_lengths, .index = l)).result
        first ::= length(halfedges).count
        loop_id ::= [loop_start + l] | convert#(.to: LoopId)(_)
        i :: UIntNative = 0
        while i < count {
            use ::= unwrap_or_abort(
                .value = _FaceUses#(Uses).get(uses, .index = cursor + i)
            ).result
            item: HalfEdge = (
                .origin   = use.origin
                .edge     = use.edge
                .next     = [[[first + [i + 1] % count] | convert#(.to: HalfEdgeId)(_)]]
                .loop     = loop_id
                .reversed = use.reversed
                .pcurve   = use.pcurve
            )
            push_assume_capacity(halfedges, .value = item)
            i = i + 1
        }
        loop: Loop = (
            .first = [first | convert#(.to: HalfEdgeId)(_)]
            .count = count
        )
        push_assume_capacity(loops, .value = loop)
        cursor = cursor + count
        l = l + 1
    }
    record: Face = (
        .first_loop = [loop_start | convert#(.to: LoopId)(_)]
        .loop_count = loop_count
        .genus      = genus
        .reversed   = reversed
    )
    push_assume_capacity(faces, .value = record)
    face = [face_index | convert#(.to: FaceId)(_)]
}
