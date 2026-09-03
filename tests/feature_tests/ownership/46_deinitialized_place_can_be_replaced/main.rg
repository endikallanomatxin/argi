Buffer : Type = (.allocation: Allocation)

release(.self: $&Buffer, .allocator: $&Allocator) -> () := {
    deinit(.self = $&self&.allocation)
}

main(.system: System) -> (.status_code: Int32) := {
    first_result ::= allocate(.self = system.allocator, .size = 1)
    match first_result {
    ..error _ { status_code = 2 }
    ..ok ~ first_payload {
    first ::= ~first_payload
    buffer :: Buffer = (.allocation = ~first)
    release(.self = $&buffer, .allocator = system.allocator)

    second_result ::= allocate(.self = system.allocator, .size = 1)
    match second_result {
    ..error _ { status_code = 3 }
    ..ok ~ second_payload {
    second ::= ~second_payload
    buffer = (.allocation = ~second)
    status_code = 0
    if buffer.allocation.size != 1 {
        status_code = 1
    }
    deinit(.self = $&buffer.allocation)
    }
    }
    }
    }
}
