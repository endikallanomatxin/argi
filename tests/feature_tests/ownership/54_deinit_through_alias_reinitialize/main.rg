main(.system: System) -> (.status_code: Int32) := {
    first_byte :: UInt8 = 3
    first ::= establish_fresh_reference#(.t: UInt8)(
        .raw = raw_pointer#(.t: UInt8)(.address = cast#(.to: UIntNative)(.value = $&first_byte)),
    )
    allocation ::= establish_allocation(.data = first, .size = 0)
    a ::= $&allocation
    b ::= $&allocation

    deinit(.self = a, .allocator = system.allocator)

    second_byte :: UInt8 = 5
    second ::= establish_fresh_reference#(.t: UInt8)(
        .raw = raw_pointer#(.t: UInt8)(.address = cast#(.to: UIntNative)(.value = $&second_byte)),
    )
    b& = establish_allocation(.data = second, .size = 0)
    if b&.size == 0 {
        status_code = 0
    } else {
        status_code = 1
    }
}
