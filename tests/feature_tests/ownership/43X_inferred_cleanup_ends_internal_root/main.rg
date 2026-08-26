Buffer : Type = (
    .allocation: Allocation
)

release(.self: $&Buffer, .allocator: $&Allocator) -> () := {
    deinit(.self = $&self&.allocation)
}

main(.system: System) -> (.status_code: Int32) := {
    allocation ::= allocate(.self = system.allocator, .size = 1)
    buffer :: Buffer = (.allocation = ~allocation)
    alias ::= buffer.allocation.data

    release(.self = $&buffer, .allocator = system.allocator)
    if alias& == 0 {
        status_code = 0
    }
}
