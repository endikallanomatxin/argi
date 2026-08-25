Buffer : Type = (
    .allocation: Allocation
)

release(.self: $&Buffer, .allocator: $&Allocator) -> () := {
    deinit(.self = $&self&.allocation, .allocator = allocator)
}

main(.system: System) -> (.status_code: Int32) := {
    byte :: UInt8 = 7
    raw ::= raw_pointer#(.t: UInt8)(.address = cast#(.to: UIntNative)(.value = $&byte))
    data ::= establish_fresh_reference#(.t: UInt8)(.raw = raw)
    allocation ::= establish_allocation(.data = data, .size = 1)
    buffer :: Buffer = (.allocation = ~allocation)
    alias ::= buffer.allocation.data

    release(.self = $&buffer, .allocator = system.allocator)
    if alias& == 7 {
        status_code = 0
    }
}
