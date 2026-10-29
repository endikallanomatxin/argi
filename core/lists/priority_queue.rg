-- A minimum heap with borrowed strict-weak ordering. Equivalent values have
-- unspecified removal order. Policy state must remain stable while populated.
PriorityQueue := #(.t: Type, .order: Type: OrderPolicy#(order, t)) (
    ._items : DynamicArray#(.t: t),
    ._order : &order
)

PriorityQueueInitArgs: Type = #(
    .t: Type, .order: Type: OrderPolicy#(order, t), .Provider: Type: Allocator
) (
    .order     : &order,
    .allocator : $&Provider,
    .capacity  : UIntNative  = 8
    ,
    .error_tracer : $&Virtual#(ErrorTracer)
)

implement#(.t: Type, .order: Type: OrderPolicy#(order, t), .Provider: Type: Allocator) Init#(
    PriorityQueue#(.t: t, .order: order), PriorityQueueInitArgs#(t, order, Provider)
) (
    .Result : Type = Errable#(PriorityQueue#(.t: t, .order: order), (..out_of_memory))

    .init = PriorityQueueInitArgs#(t, order, Provider) -> (.result: Result) {
        assume error_tracer

        _init_order ::= order
        _init_allocator ::= allocator
        _init_capacity ::= capacity

        assume allocator := _init_allocator
        items ::= DynamicArray#(.t: t)(.allocator = _init_allocator, .capacity = _init_capacity)!

        result = ..ok(._items = ~items, ._order = _init_order)
    }
)

implement#(.t: Type, .order: Type: OrderPolicy#(order, t)) Deinit#(
    PriorityQueue#(.t: t, .order: order)
) (
    .deinit = (.self: $&PriorityQueue#(.t: t, .order: order)) -> () {
        deinit(.self = $&self&._items)
    }
)

_collection_length_priority_queue := #(.t: Type, .order: Type: OrderPolicy#(order, t)) (
    .self : &PriorityQueue#(.t: t, .order: order)
) -> (.count: UIntNative) { count = length(&self&._items).count }

implement#(.t: Type, .order: Type: OrderPolicy#(order, t)) CollectionLength#(
    PriorityQueue#(.t: t, .order: order)
) (
    .measure_length = _collection_length_priority_queue
)

_queue_push_priority_queue := #(
    .t: Type, .order: Type: OrderPolicy#(order, t), .Provider: Type: Allocator
) (
    .self         : $&PriorityQueue#(.t: t, .order: order),
    .value        : t,
    .allocator    : $&Provider,
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: Errable#(Void, (..out_of_memory)) = ..ok Void()) {
    assume error_tracer

    assume allocator
    owned ::= ~value

    if self&._items._length == integer_limits(.value = self&._items._length).maximum {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    ensure_capacity(
        .self      = $&self&._items
        .capacity  = length(&self&._items).count + 1
        .allocator = allocator
    )!
    push_assume_capacity($&self&._items, .value = ~owned)
    child ::= length(&self&._items).count - 1

    while child > 0 {
        parent ::= [child - 1] / 2
        a ::= unwrap_or_abort(.value = get_reference(&self&._items, .index = child))
        b ::= unwrap_or_abort(.value = get_reference(&self&._items, .index = parent))
        if OrderPolicy#(order, t).less(self&._order, .left = a, .right = b).ok == false {
            return
        }
        _swap_owned_array#(.t: t)($&self&._items, .left = child, .right = parent)
        child = parent
    }
}

peek_reference := #(.t: Type, .order: Type: OrderPolicy#(order, t)) (
    .self : &PriorityQueue#(.t: t, .order: order)
) -> (.value: ?&t = ..none) {
    if length(&self&._items).count == 0 { return }
    value = ..some(
        .value = _trusted_dynamic_array_get_reference#(.t: t)(
            .array = &self&._items, .index = 0
        ).reference
    )
}

_queue_pop_priority_queue := #(.t: Type, .order: Type: OrderPolicy#(order, t)) (
    .self: $&PriorityQueue#(.t: t, .order: order), .error_tracer: $&Virtual#(ErrorTracer)
) -> (.result: ?t = ..none) {
    assume error_tracer
    count ::= length(&self&._items).count

    if count == 0 { return }
    _swap_owned_array#(.t: t)($&self&._items, .left = 0, .right = count - 1)
    extracted ::= ~unwrap_or_abort(
        .value = Removable#(DynamicArray#(.t: t)).pop($&self&._items)
    )
    result = ..some(.value = ~extracted)
    count = count - 1
    root :: UIntNative = 0

    while root < count / 2 {
        child ::= root * 2 + 1
        if child + 1 < count {
            left ::= unwrap_or_abort(.value = get_reference(&self&._items, .index = child))
            right ::= unwrap_or_abort(.value = get_reference(&self&._items, .index = child + 1))
            if OrderPolicy#(order, t).less(self&._order, .left = right, .right = left).ok {
                child = [child + 1]
            }
        }
        a ::= unwrap_or_abort(.value = get_reference(&self&._items, .index = child))
        b ::= unwrap_or_abort(.value = get_reference(&self&._items, .index = root))
        if OrderPolicy#(order, t).less(self&._order, .left = a, .right = b).ok == false {
            return
        }
        _swap_owned_array#(.t: t)($&self&._items, .left = root, .right = child)
        root = child
    }
}

implement#(.t: Type, .order: Type: OrderPolicy#(order, t)) Queue#(
    PriorityQueue#(.t: t, .order: order)
) (
    .Item   : Type = t
    .Result : Type = ?t
    .pop    = _queue_pop_priority_queue
)

implement#(.t: Type, .order: Type: OrderPolicy#(order, t), .Provider: Type: Allocator) QueueInsertion#(
    PriorityQueue#(.t: t, .order: order), Provider
) (
    .Result : Type = Errable#(Void, (..out_of_memory))
    .push   = _queue_push_priority_queue
)

peek := #(.t: Type: ImplicitlyCopyable, .order: Type: OrderPolicy#(order, t)) (
    .self : &PriorityQueue#(.t: t, .order: order)
) -> (.value: ?t = ..none) {
    assume error_tracer ::= NoopErrorTracer() | to_virtual#(.contract: ErrorTracer)($&_) | $&_
    if length(&self&._items).count == 0 { return }
    value = ..some(
        .value = unwrap_or_abort(.value = get_reference(&self&._items, .index = 0))&
    )
}
