main(.system: System) -> (.status_code: Int32) := {
    byte :: UInt8 = 3
    data ::= establish_fresh_reference#(.t: UInt8)(
        .raw = raw_pointer#(.t: UInt8)(.address = cast#(.to: UIntNative)(.value = $&byte)),
    )
    allocation ::= establish_allocation(.data = data, .size = 0)
    a ::= $&allocation
    b ::= $&allocation

    deinit(.self = a, .allocator = system.allocator)
    if b&.size == 0 {
        status_code = 0
    }
}
