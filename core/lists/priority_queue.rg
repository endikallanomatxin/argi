-- A minimum heap with borrowed strict-weak ordering. Equivalent values have
-- unspecified removal order. Policy state must remain stable while populated.
PriorityQueue#(.t: Type: ImplicitlyCopyable, .order: Type: OrderPolicy#(.t: t)): Type = (
    ._items : DynamicArray#(.t: t),
    ._order : &order
)

PriorityQueue init#(
        .t     : Type: ImplicitlyCopyable,
        .order : Type: OrderPolicy#(.t: t)
    )(
        .order     : &order,
        .allocator : $&Allocator,
        .capacity  : UIntNative   = 8
    ) -> (
        .result : Errable#(PriorityQueue#(.t: t, .order: order), (..out_of_memory))
    ) := {
    assume allocator
    items ::= DynamicArray#(.t: t)(.allocator = allocator, .capacity = capacity)!

    result = ..ok(._items = ~items, ._order = order)
}

PriorityQueue deinit#(
        .t     : Type: ImplicitlyCopyable,
        .order : Type: OrderPolicy#(.t: t)
    )(
        .self      : $&PriorityQueue#(.t: t, .order: order),
        .allocator : $&Allocator
    ) -> () := {
    assume allocator
    deinit(.self = $&self&._items, .allocator = allocator)
}

length#(
        .t     : Type: ImplicitlyCopyable,
        .order : Type: OrderPolicy#(.t: t)
    )(
        .self : &PriorityQueue#(.t: t, .order: order)
    ) -> (
        .count : UIntNative
    ) := { count = length(&self&._items).count }

push#(
        .t     : Type: ImplicitlyCopyable,
        .order : Type: OrderPolicy#(.t: t)
    )(
        .self      : $&PriorityQueue#(.t: t, .order: order),
        .value     : t,
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(Void, (..out_of_memory)) = ..ok Void()
    ) := {
    assume allocator
    push(.self = $&self&._items, .value = value, .allocator = allocator)!
    child ::= length(&self&._items).count - 1

    while child > 0 {
        parent ::= [child - 1] / 2
        a ::= unwrap_or_abort(.value = get_ro_ref(.self = &self&._items, .index = child))&
        b ::= unwrap_or_abort(.value = get_ro_ref(.self = &self&._items, .index = parent))&
        if less(.self = self&._order, .left = a, .right = b).ok == false { return }
        _swap_indexed_values#(.t: t)(.self = $&self&._items, .left = child, .right = parent)
        child = parent
    }
}

peek#(
        .t     : Type: ImplicitlyCopyable,
        .order : Type: OrderPolicy#(.t: t)
    )(
        .self : &PriorityQueue#(.t: t, .order: order)
    ) -> (
        .value : ?t = ..none
    ) := {
    if length(&self&._items).count == 0 { return }
    value = ..some(
        .value = unwrap_or_abort(.value = get_ro_ref(.self = &self&._items, .index = 0))&
    )
}

pop#(
        .t     : Type: ImplicitlyCopyable,
        .order : Type: OrderPolicy#(.t: t)
    )(
        .self : $&PriorityQueue#(.t: t, .order: order)
    ) -> (
        .value : ?t = ..none
    ) := {
    count ::= length(&self&._items).count

    if count == 0 { return }
    value = peek(.self = self).value
    _swap_indexed_values#(.t: t)(.self = $&self&._items, .left = 0, .right = count - 1)
    discarded ::= pop(.self = $&self&._items)
    count = count - 1
    root :: UIntNative = 0

    while root < count / 2 {
        child ::= root * 2 + 1
        if child + 1 < count {
            left ::= unwrap_or_abort(.value = get_ro_ref(.self = &self&._items, .index = child))&
            right ::= unwrap_or_abort(
                .value = get_ro_ref(.self = &self&._items, .index = child + 1)
            )&
            if less(.self = self&._order, .left = right, .right = left).ok { child = child + 1 }
        }
        a ::= unwrap_or_abort(.value = get_ro_ref(.self = &self&._items, .index = child))&
        b ::= unwrap_or_abort(.value = get_ro_ref(.self = &self&._items, .index = root))&
        if less(.self = self&._order, .left = a, .right = b).ok == false { return }
        _swap_indexed_values#(.t: t)(.self = $&self&._items, .left = root, .right = child)
        root = child
    }
}
