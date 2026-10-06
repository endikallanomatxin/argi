drops :: Int32 = 0

Tracked: Type = (.id: Int32)

Tracked deinit(.self: $&Tracked) -> () := { drops = drops + 1 }

Pair: Type = (.a: Tracked, .b: Tracked)

PairOrder: Type = ()

PairOrder implements BorrowedOrderPolicy#(.t: Pair)

less(.self: &PairOrder, .left: &Pair, .right: &Pair) -> (.ok: Bool) := {
    ok = [
        left&.a.id
        < right&.a.id
    ]
}

RefusingAllocator: Type = ()

RefusingAllocator implements Allocator

allocate(
        .self      : $&RefusingAllocator,
        .size      : UIntNative,
        .alignment : UIntNative           = 1
    ) -> (
        .result : Errable#(.t: Allocation, .reasons: (..out_of_memory))
    ) := {
    result = ..error(.reason = ..out_of_memory)
}

run_main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    order ::= PairOrder()
    items ::= DynamicArray#(.t: Pair)(.allocator = allocator, .capacity = 3)!
    push_assume_capacity(
        .self  = $&items
        .value = Pair(.a = Tracked(.id = 3), .b = Tracked(.id = 30))
    )
    push_assume_capacity(
        .self  = $&items
        .value = Pair(.a = Tracked(.id = 1), .b = Tracked(.id = 10))
    )
    push_assume_capacity(
        .self  = $&items
        .value = Pair(.a = Tracked(.id = 2), .b = Tracked(.id = 20))
    )
    sort_owned(.self = $&items, .order = &order)
    if unwrap_or_abort(.value = get_ro_ref(.self = &items, .index = 0))&.a.id != 1 { abort }
    reverse_owned(.self = $&items)
    if unwrap_or_abort(.value = get_ro_ref(.self = &items, .index = 0))&.a.id != 3 { abort }
    if drops != 0 { abort }
    for ~item in items { if item.b.id != item.a.id * 10 { abort } }
    if drops != 6 { abort }
    queue ::= OwnedPriorityQueue#(.t: Pair, .order: PairOrder)(
        .order     = &order
        .allocator = allocator
        .capacity  = 1
    )!
    push(
        .self      = $&queue
        .value     = Pair(.a = Tracked(.id = 3), .b = Tracked(.id = 30))
        .allocator = allocator
    )!
    push(
        .self      = $&queue
        .value     = Pair(.a = Tracked(.id = 1), .b = Tracked(.id = 10))
        .allocator = allocator
    )!
    push(
        .self      = $&queue
        .value     = Pair(.a = Tracked(.id = 2), .b = Tracked(.id = 20))
        .allocator = allocator
    )!
    match peek_ref(.self = &queue).value {
        ..none { abort } ..some entry { if entry.value&.a.id != 1 { abort } }
    }
    match pop(.self = $&queue).value {
        ..none { abort } ..some ~entry { if entry.value.a.id != 1 { abort } }
    }
    if drops != 8 { abort }
    deinit(.self = $&queue, .allocator = allocator)
    if drops != 12 { abort }
    refusal ::= RefusingAllocator()
    bounded ::= OwnedPriorityQueue#(.t: Pair, .order: PairOrder)(
        .order     = &order
        .allocator = allocator
        .capacity  = 1
    )!
    push(
        .self      = $&bounded
        .value     = Pair(.a = Tracked(.id = 4), .b = Tracked(.id = 40))
        .allocator = allocator
    )!
    match push(
        .self      = $&bounded
        .value     = Pair(.a = Tracked(.id = 5), .b = Tracked(.id = 50))
        .allocator = $&refusal
    ) {
        ..ok _ { abort }
        ..error error { if error.reason != ..out_of_memory { abort } }
    }
    if drops != 14 or length(.self = &bounded).count != 1 { abort }
    match peek_ref(.self = &bounded).value {
        ..none { abort } ..some entry { if [
                entry.value&.a.id
                != 4
            ] { abort } }
    }
    deinit(.self = $&bounded, .allocator = allocator)
    if drops != 16 { abort }
}

main(.system: System, .writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
