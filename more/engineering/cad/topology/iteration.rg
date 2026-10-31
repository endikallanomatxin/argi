-- Each entry carries identity plus a copy of the oriented half-edge data.
-- The range borrows the model, but returned entries do not borrow its storage.
HalfEdgeEntry := (.id: HalfEdgeId, .halfedge: HalfEdge)

implement ImplicitlyCopyable#(HalfEdgeEntry) ()

LoopHalfEdges := (
    ._topology : &Topology,
    ._first    : HalfEdgeId,
    ._count    : UIntNative
)

LoopHalfEdgeIterator := (
    ._topology  : &Topology,
    ._current   : HalfEdgeId,
    ._remaining : UIntNative
)

-- Validates the loop ID once. The immutable model guarantees its links and
-- count agree; following next works independently of physical storage order.
_topology_loop_halfedges := (.topology: &Topology, .loop: LoopId) -> (
    .result : Errable#(LoopHalfEdges, (..out_of_bounds))
) {
    boundary ::= _topology_loop_info(topology, .loop = loop)!
    result = ..ok(._topology = topology, ._first = boundary.first, ._count = boundary.count)
}

implement Iterable#(LoopHalfEdges) (
    .Item         : Type = HalfEdgeEntry
    .IteratorType : Type = LoopHalfEdgeIterator

    .to_iterator = (.value: &LoopHalfEdges) -> (.iterator: LoopHalfEdgeIterator) {
        iterator = (
            ._topology  = value&._topology
            ._current   = value&._first
            ._remaining = value&._count
        )
    }
)

implement Iterator#(LoopHalfEdgeIterator) (
    .Item : Type = HalfEdgeEntry

    .has_next = (.self: &LoopHalfEdgeIterator) -> (.ok: Bool) {
        ok = self&._remaining > 0
    }

    .next = (.self: $&LoopHalfEdgeIterator) -> (.value: HalfEdgeEntry) {
        -- Like core iterators, next requires has_next. Exhaustion never wraps
        -- around the loop and starts yielding its first half-edge again.
        if self&._remaining == 0 { abort }
        current ::= self&._current
        item ::= unwrap_or_abort(
            .value = _topology_halfedge_info(self&._topology, .halfedge = current)
        ).result
        value = (.id = current, .halfedge = item)
        self&._current = item.next
        self&._remaining = self&._remaining - 1
    }
)

loop_halfedges := #(.Scalar: Type: Float) (.model: &Model#(Scalar), .loop: LoopId) -> (
    .result : Errable#(LoopHalfEdges, (..out_of_bounds))
) {
    boundary ::= loop_info(model, .loop = loop)!
    result = ..ok(
        ._topology = &model&._topology
        ._first    = boundary.first
        ._count    = boundary.count
    )
}

FaceLoopEntry := (.id: LoopId, .loop: Loop)

implement ImplicitlyCopyable#(FaceLoopEntry) ()

FaceLoops := (._topology: &Topology, ._first: UIntNative, ._count: UIntNative)

FaceLoopIterator := (._topology: &Topology, ._next: UIntNative, ._remaining: UIntNative)

-- Boundary components have no universal outer/hole order on periodic supports.
-- The empty range is valid for closed faces such as a sphere or torus.
face_loops := #(.Scalar: Type: Float) (.model: &Model#(Scalar), .face: FaceId) -> (
    .result : Errable#(FaceLoops, (..out_of_bounds))
) {
    item ::= face_info(model, .face = face)!
    result = ..ok(
        ._topology = &model&._topology
        ._first    = [item.first_loop | convert#(.to: UIntNative)(_)]
        ._count    = item.loop_count
    )
}

implement Iterable#(FaceLoops) (
    .Item         : Type = FaceLoopEntry
    .IteratorType : Type = FaceLoopIterator
    .to_iterator  = (.value: &FaceLoops) -> (.iterator: FaceLoopIterator) {
        iterator = (
            ._topology = value&._topology, ._next = value&._first, ._remaining = value&._count
        )
    }
)

implement Iterator#(FaceLoopIterator) (
    .Item     : Type = FaceLoopEntry
    .has_next = (.self: &FaceLoopIterator) -> (.ok: Bool) { ok = self&._remaining > 0 }
    .next     = (.self: $&FaceLoopIterator) -> (.value: FaceLoopEntry) {
        if self&._remaining == 0 { abort }
        id ::= self&._next | convert#(.to: LoopId)(_)
        item ::= unwrap_or_abort(
            .value = _topology_loop_info(self&._topology, .loop = id)
        ).result
        value = (.id = id, .loop = item)
        self&._next = self&._next + 1
        self&._remaining = self&._remaining - 1
    }
)
