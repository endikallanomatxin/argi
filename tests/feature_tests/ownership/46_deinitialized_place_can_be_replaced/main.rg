Buffer : Type = (.allocation: Allocation)

release(.self: $&Buffer, .allocator: $&Allocator) -> () := {
    deinit(.self = $&self&.allocation, .allocator = allocator)
}

main(.system: System) -> (.status_code: Int32) := {
    first ::= allocate_owned(.self = system.allocator, .size = 1)
    buffer :: Buffer = (.allocation = ~first)
    release(.self = $&buffer, .allocator = system.allocator)

    second ::= allocate_owned(.self = system.allocator, .size = 1)
    buffer = (.allocation = ~second)
    status_code = 0
    if buffer.allocation.size != 1 {
        status_code = 1
    }
    deinit(.self = $&buffer.allocation, .allocator = system.allocator)
}
