Buffer : Type = (.data: $&UInt8)

release(.self: $&Buffer, .allocator: $&Allocator) -> () := {
    deallocate(.self = allocator, .data = self&.data, .size = 1)
}

main(.system: System) -> (.status_code: Int32) := {
    first_byte :: UInt8 = 3
    first ::= establish_fresh_reference#(.t: UInt8)(.raw = raw_pointer#(.t: UInt8)(.address = cast#(.to: UIntNative)(.value = $&first_byte)))
    buffer :: Buffer = (.data = first)
    release(.self = $&buffer, .allocator = system.allocator)

    second_byte :: UInt8 = 5
    second ::= establish_fresh_reference#(.t: UInt8)(.raw = raw_pointer#(.t: UInt8)(.address = cast#(.to: UIntNative)(.value = $&second_byte)))
    buffer = (.data = second)
    status_code = 0
    if buffer.data& != 5 {
        status_code = 1
    }
    deallocate(.self = system.allocator, .data = second, .size = 1)
}
