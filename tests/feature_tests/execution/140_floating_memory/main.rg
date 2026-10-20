Numbers: Type = (.half: Float16, .single: Float32, .double: Float64, .values: [2]Float32)

exercise := () -> (.result: Int32) {
    original :: Numbers = (
        .half   = 1.5
        .single = 16777216.0
        .double = 16777217.0
        .values = (17.0, 25.0)
    )
    restored :: Numbers = (.half = 0.0, .single = 0.0, .double = 0.0, .values = (0.0, 0.0))
    source ::= trusted_reinterpret_reference#(.from: Numbers, .to: UInt8)(
        .base = &original
    ).reference
    destination ::= trusted_mutable_reinterpret_reference#(.from: Numbers, .to: UInt8)(
        .base = $&restored
    ).reference
    index :: UIntNative = 0
    while index < size_of(.type = Numbers) {
        input ::= trusted_reference_offset#(.t: UInt8)(
            .base = source, .elements = index
        ).reference
        output ::= trusted_mutable_reference_offset#(.t: UInt8)(
            .base = destination, .elements = index
        ).reference
        output&= input&
        index = index + 1
    }
    if [
        restored.half != 1.5
        or restored.single + 1.0 != 16777216.0
        or restored.double != 16777217.0
    ] { abort }
    if restored.values[0] + restored.values[1] != 42.0 { abort }
    result = 42
}

main := () -> (.status_code: Int32) {
    if #run exercise() != 42 { abort }
    if exercise() != 42 { abort }
    assume ffi ::= $&ForeignFunctionInterface()
    address ::= aligned_alloc(.alignment = 8, .size = size_of(.type = Numbers)).address
    if address == 0 { abort }
    anchor :: UInt8 = 0
    raw ::= raw_pointer#(.t: Numbers)(.address = address).raw
    reference ::= trusted_establish_inherited_reference#(.t: Numbers)(
        .raw = raw, .root = erase_reference#(.t: UInt8)(.base = &anchor).reference
    ).reference
    reference&.half = 1.5
    reference&.single = 16777216.0
    reference&.double = 16777217.0
    reference&.values[0] = 17.0
    reference&.values[1] = 25.0
    snapshot ::= reference&
    if [
        snapshot.half != 1.5
        or snapshot.single + 1.0 != 16777216.0
        or snapshot.double != 16777217.0
    ] { abort }
    if snapshot.values[0] + snapshot.values[1] != 42.0 { abort }
    aligned_free(.address = address)
    status_code = 42
}
