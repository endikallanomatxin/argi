Pair := (.left: Int32, .right: Int32)

observe := (.calls: $&Int32, .reference: $&Int32) -> (.result: $&Int32) {
    calls&= calls&+ 1
    result = reference
}

main := () -> (.status_code: Int32) {
    assume ffi ::= $&ForeignFunctionInterface()
    address ::= aligned_alloc(.alignment = 8, .size = 32).address
    if address == 0 { abort }
    anchor :: UInt8 = 0
    root ::= erase_reference<.t: UInt8>(.base = &anchor).reference
    first ::= raw_pointer<.t: Int32>(.address = address).raw
    second ::= raw_pointer<.t: Int32>(.address = address + 4).raw
    source ::= trusted_establish_inherited_reference<.t: Int32>(
        .raw = first, .root = root
    ).reference
    destination ::= trusted_establish_inherited_reference<.t: Int32>(
        .raw = second, .root = root
    ).reference
    source&= 42
    calls :: Int32 = 0
    trusted_opaque_relocate(
        .source      = observe(.calls = $&calls, .reference = source)
        .destination = observe(.calls = $&calls, .reference = destination)
    )
    if calls != 2 { abort }
    if destination&!= 42 { abort }
    pair_source ::= trusted_establish_inherited_reference<.t: Pair>(
        .raw = raw_pointer<.t: Pair>(.address = address + 8).raw, .root = root
    ).reference
    pair_destination ::= trusted_establish_inherited_reference<.t: Pair>(
        .raw = raw_pointer<.t: Pair>(.address = address + 16).raw, .root = root
    ).reference
    pair_source&.left = 17
    pair_source&.right = 25
    trusted_opaque_relocate(.source = pair_source, .destination = pair_destination)
    if pair_destination&.left + pair_destination&.right != 42 { abort }
    aligned_free(.address = address)
    status_code = 42
}
