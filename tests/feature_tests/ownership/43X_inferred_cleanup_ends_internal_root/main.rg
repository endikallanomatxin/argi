Buffer : Type = (
    .data: $&UInt8
)

release(.self: $&Buffer, .allocator: $&Allocator) -> () := {
    deallocate(.self = allocator, .data = self&.data, .size = 1)
}

main(.system: System) -> (.status_code: Int32) := {
    byte :: UInt8 = 7
    raw ::= raw_pointer#(.t: UInt8)(.address = cast#(.to: UIntNative)(.value = $&byte))
    data ::= establish_fresh_reference#(.t: UInt8)(.raw = raw)
    buffer :: Buffer = (.data = data)

    release(.self = $&buffer, .allocator = system.allocator)
    if data& == 7 {
        status_code = 0
    }
}
