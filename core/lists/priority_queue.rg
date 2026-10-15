-- A minimum heap with borrowed strict-weak ordering. Equivalent values have
-- unspecified removal order. Policy state must remain stable while populated.
PriorityQueue#(.t: Type: ImplicitlyCopyable, .order: Type: OrderPolicy#(order, t)): Type = (
    ._items : DynamicArray#(.t: t),
    ._order : &order
)

implement#(
    .t        : Type: ImplicitlyCopyable,
    .order    : Type: OrderPolicy#(order, t),
    .Provider : Type: Allocator
) Init#(
    PriorityQueue#(.t: t, .order: order),
    (.order: &order, .allocator: $&Provider = reach allocator, .capacity: UIntNative = 8)
) (
    .Result : Type = Errable#(PriorityQueue#(.t: t, .order: order), (..out_of_memory))
    .init   = (
        .args : (
            .order: &order, .allocator: $&Provider = reach allocator, .capacity: UIntNative = 8
        )
    ) -> (.result: Result) {
        order ::= args.order
        allocator ::= args.allocator
        capacity ::= args.capacity

        assume allocator
        items ::= DynamicArray#(.t: t)(.allocator = allocator, .capacity = capacity)!

        result = ..ok(._items = ~items, ._order = order)
    }
)

implement#(.t: Type: ImplicitlyCopyable, .order: Type: OrderPolicy#(order, t)) Deinit#(
    PriorityQueue#(.t: t, .order: order)
) (
    .deinit = (.self: $&PriorityQueue#(.t: t, .order: order)) -> () {
        deinit(.self = $&self&._items)
    }
)

_collection_length_priority_queue#(
    .t: Type: ImplicitlyCopyable, .order: Type: OrderPolicy#(order, t)
)(.self: &PriorityQueue#(.t: t, .order: order)) -> (.count: UIntNative) := {
    count = length(&self&._items).count
}

implement#(.t: Type: ImplicitlyCopyable, .order: Type: OrderPolicy#(order, t)) CollectionLength#(
    PriorityQueue#(.t: t, .order: order)
) (
    .measure_length = _collection_length_priority_queue
)

_queue_push_priority_queue#(
    .t        : Type: ImplicitlyCopyable,
    .order    : Type: OrderPolicy#(order, t),
    .Provider : Type: Allocator
)(.self: $&PriorityQueue#(.t: t, .order: order), .value: t, .allocator: $&Provider) -> (
    .result : Errable#(Void, (..out_of_memory)) = ..ok Void()
) := {
    assume allocator
    Resizable#(
        DynamicArray#(.t: t), Provider
    ).push(.self = $&self&._items, .value = value, .allocator = allocator)!
    child ::= length(&self&._items).count - 1

    while child > 0 {
        parent ::= [child - 1] / 2
        a ::= unwrap_or_abort(.value = get_ro_ref(&self&._items, .index = child))&
        b ::= unwrap_or_abort(.value = get_ro_ref(&self&._items, .index = parent))&
        if OrderPolicy#(order, t).less(self&._order, .left = a, .right = b).ok == false {
            return
        }
        _swap_indexed_values#(.t: t)($&self&._items, .left = child, .right = parent)
        child = parent
    }
}

peek#(.t: Type: ImplicitlyCopyable, .order: Type: OrderPolicy#(order, t))(
    .self : &PriorityQueue#(.t: t, .order: order)
) -> (.value: ?t = ..none) := {
    if length(&self&._items).count == 0 { return }
    value = ..some(
        .value = unwrap_or_abort(.value = get_ro_ref(&self&._items, .index = 0))&
    )
}

_queue_pop_priority_queue#(.t: Type: ImplicitlyCopyable, .order: Type: OrderPolicy#(order, t))(
    .self : $&PriorityQueue#(.t: t, .order: order)
) -> (.result: ?t = ..none) := {
    count ::= length(&self&._items).count

    if count == 0 { return }
    result = peek(self).value
    _swap_indexed_values#(.t: t)($&self&._items, .left = 0, .right = count - 1)
    discarded ::= Removable#(DynamicArray#(.t: t)).pop($&self&._items)
    count = count - 1
    root :: UIntNative = 0

    while root < count / 2 {
        child ::= root * 2 + 1
        if child + 1 < count {
            left ::= unwrap_or_abort(.value = get_ro_ref(&self&._items, .index = child))&
            right ::= unwrap_or_abort(.value = get_ro_ref(&self&._items, .index = child + 1))&
            if OrderPolicy#(order, t).less(self&._order, .left = right, .right = left).ok {
                child = [child + 1]
            }
        }
        a ::= unwrap_or_abort(.value = get_ro_ref(&self&._items, .index = child))&
        b ::= unwrap_or_abort(.value = get_ro_ref(&self&._items, .index = root))&
        if OrderPolicy#(order, t).less(self&._order, .left = a, .right = b).ok == false {
            return
        }
        _swap_indexed_values#(.t: t)($&self&._items, .left = root, .right = child)
        root = child
    }
}

implement#(.t: Type: ImplicitlyCopyable, .order: Type: OrderPolicy#(order, t)) Queue#(
    PriorityQueue#(.t: t, .order: order)
) (
    .Item   : Type = t
    .Result : Type = ?t
    .pop    = _queue_pop_priority_queue
)

implement#(
    .t        : Type: ImplicitlyCopyable,
    .order    : Type: OrderPolicy#(order, t),
    .Provider : Type: Allocator
) QueueInsertion#(PriorityQueue#(.t: t, .order: order), Provider) (
    .Result : Type = Errable#(Void, (..out_of_memory))
    .push   = _queue_push_priority_queue
)
