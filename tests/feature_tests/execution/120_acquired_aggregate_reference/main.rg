Pair: Type = (.left: Int32, .right: Int32)

main := () -> (.status_code: Int32) {
    assume ffi ::= $&ForeignFunctionInterface()
    address ::= aligned_alloc(.alignment = 8, .size = 16).address
    if address == 0 { abort }
    anchor :: UInt8 = 0
    raw ::= raw_pointer#(.t: Pair)(.address = address).raw
    reference ::= trusted_establish_inherited_reference#(.t: Pair)(
        .raw = raw, .root = erase_reference#(.t: UInt8)(.base = &anchor).reference
    ).reference
    reference&.left = 17
    reference&.right = 25
    status_code = reference&.left + reference&.right
    aligned_free(.address = address)
}
