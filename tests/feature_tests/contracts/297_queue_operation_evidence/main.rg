SmallOrder: Type = ()

implement OrderPolicy#(SmallOrder, UInt8) (
    .less = (.self: &SmallOrder, .left: &UInt8, .right: &UInt8) -> (.ok: Bool) {
        ok = left&< right&
    }
)

take_queue := #(.Collection: Type: Queue#(Collection)) (.self: $&Collection) -> (
    .result : Queue#(Collection).Result
) {

    result = ~Queue#(Collection).pop(.self = self)
}

main := (.system: System) -> (.status_code: Int32 = 0) {

    assume allocator := system.page_allocator
    ring ::= unwrap_or_abort(.value = RingBuffer#(UInt8)(.capacity = 1, .allocator = allocator))
    unwrap_or_abort(.value = push(.self = $&ring, .value = 250))
    match push(.self = $&ring, .value = 251) {
        ..ok _ { status_code = 1 }
        ..error item { if item.reason != ..full { status_code = 2 } }
    }
    if unwrap_or_abort(.value = take_queue(.self = $&ring)) != 250 { status_code = 3 }
    match take_queue(.self = $&ring) {
        ..ok _ { status_code = 4 }
        ..error item { if item.reason != ..empty { status_code = 5 } }
    }

    order ::= SmallOrder()
    heap ::= unwrap_or_abort(
        .value = PriorityQueue#(UInt8, SmallOrder)(
            .order = &order, .allocator = allocator, .capacity = 1
        )
    )
    unwrap_or_abort(.value = push(.self = $&heap, .value = 250))
    unwrap_or_abort(.value = push(.self = $&heap, .value = 5))
    match take_queue(.self = $&heap) {
        ..none { status_code = 6 }
        ..some item { if item.value != 5 { status_code = 7 } }
    }
    match take_queue(.self = $&heap) {
        ..none { status_code = 8 }
        ..some item { if item.value != 250 { status_code = 9 } }
    }
    match take_queue(.self = $&heap) {
        ..none {}
        ..some _ { status_code = 10 }
    }
}
