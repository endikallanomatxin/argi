main := () -> (.status_code: Int32) {
    assume ffi ::= $&ForeignFunctionInterface()
    address ::= aligned_alloc(.alignment = 8, .size = 16).address
    if address == 0 { abort }
    anchor :: UInt8 = 0
    raw ::= raw_pointer<.t: Int32>(.address = address).raw
    reference ::= trusted_establish_inherited_reference<.t: Int32>(
        .raw = raw, .root = erase_reference<.t: UInt8>(.base = &anchor).reference
    ).reference
    reference&= 42
    status_code = reference&
    aligned_free(.address = address)
}
