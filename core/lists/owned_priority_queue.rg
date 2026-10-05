-- A minimum heap with borrowed strict-weak ordering. Equivalent values have
-- unspecified removal order. Policy state must remain stable while populated.
OwnedPriorityQueue#(.t: Type, .order: Type: BorrowedOrderPolicy#(.t: t)): Type = (
    ._items : DynamicArray#(.t: t),
    ._order : &order
)

OwnedPriorityQueue init#(
        .t     : Type,
        .order : Type: BorrowedOrderPolicy#(.t: t)
    )(
        .order     : &order,
        .allocator : $&Allocator,
        .capacity  : UIntNative   = 8
    ) -> (
        .result : Errable#(
            .t       : OwnedPriorityQueue#(.t: t, .order: order),
            .reasons : (..out_of_memory)
        )
    ) := {
    assume allocator
    items ::= DynamicArray#(.t: t)(.allocator = allocator, .capacity = capacity)!
    result = ..ok(._items = ~items, ._order = order)
}

OwnedPriorityQueue deinit#(
        .t     : Type,
        .order : Type: BorrowedOrderPolicy#(.t: t)
    )(
        .self      : $&OwnedPriorityQueue#(.t: t, .order: order),
        .allocator : $&Allocator
    ) -> () := {
    assume allocator
    while length(.self = &self&._items).count > 0 {
        discarded ::= ~unwrap_or_abort(.value = pop(.self = $&self&._items))
    }
    deinit(.self = $&self&._items, .allocator = allocator)
}

length#(
        .t     : Type,
        .order : Type: BorrowedOrderPolicy#(.t: t)
    )(
        .self : &OwnedPriorityQueue#(.t: t, .order: order)
    ) -> (
        .count : UIntNative
    ) := { count = length(.self = &self&._items).count }

push#(
        .t     : Type,
        .order : Type: BorrowedOrderPolicy#(.t: t)
    )(
        .self      : $&OwnedPriorityQueue#(.t: t, .order: order),
        .value     : t,
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..out_of_memory)) = ..ok Void()
    ) := {
    assume allocator
    owned ::= ~value
    if self&._items._length == integer_limits(.value = self&._items._length).maximum {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    ensure_capacity(
        .self      = $&self&._items
        .capacity  = length(.self = &self&._items).count + 1
        .allocator = allocator
    )!
    push_assume_capacity(.self = $&self&._items, .value = ~owned)
    child ::= length(.self = &self&._items).count - 1
    while child > 0 {
        parent ::= [child - 1] / 2
        a ::= unwrap_or_abort(.value = get_ro_ref(.self = &self&._items, .index = child))
        b ::= unwrap_or_abort(.value = get_ro_ref(.self = &self&._items, .index = parent))
        if less(.self = self&._order, .left = a, .right = b).ok == false { return }
        _swap_owned_array#(.t: t)(.self = $&self&._items, .left = child, .right = parent)
        child = parent
    }
}

peek_ref#(
        .t     : Type,
        .order : Type: BorrowedOrderPolicy#(.t: t)
    )(
        .self : &OwnedPriorityQueue#(.t: t, .order: order)
    ) -> (
        .value : ?&t = ..none
    ) := {
    if length(.self = &self&._items).count == 0 { return }
    value = ..some(
        .value = _trusted_dynamic_array_get_ro_ref#(.t: t)(.array = &self&._items, .index = 0).reference
    )
}

pop#(
        .t     : Type,
        .order : Type: BorrowedOrderPolicy#(.t: t)
    )(
        .self : $&OwnedPriorityQueue#(.t: t, .order: order)
    ) -> (
        .value : ?t = ..none
    ) := {
    count ::= length(.self = &self&._items).count
    if count == 0 { return }
    _swap_owned_array#(.t: t)(.self = $&self&._items, .left = 0, .right = count - 1)
    extracted ::= ~unwrap_or_abort(.value = pop(.self = $&self&._items))
    value = ..some(.value = ~extracted)
    count = count - 1
    root :: UIntNative = 0
    while root < count / 2 {
        child ::= root * 2 + 1
        if child + 1 < count {
            left ::= unwrap_or_abort(.value = get_ro_ref(.self = &self&._items, .index = child))
            right ::= unwrap_or_abort(
                .value = get_ro_ref(.self = &self&._items, .index = child + 1)
            )
            if less(.self = self&._order, .left = right, .right = left).ok { child = child + 1 }
        }
        a ::= unwrap_or_abort(.value = get_ro_ref(.self = &self&._items, .index = child))
        b ::= unwrap_or_abort(.value = get_ro_ref(.self = &self&._items, .index = root))
        if less(.self = self&._order, .left = a, .right = b).ok == false { return }
        _swap_owned_array#(.t: t)(.self = $&self&._items, .left = root, .right = child)
        root = child
    }
}
