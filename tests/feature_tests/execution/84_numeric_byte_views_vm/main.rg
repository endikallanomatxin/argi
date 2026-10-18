Record: Type = (.first: UInt32, .second: UInt32)

exercise := () -> (.result: Int32) {
    value :: Record = (.first = 0, .second = 42)
    bytes ::= trusted_mutable_reinterpret_reference#(.from: Record, .to: UInt8)(
        .base = $&value
    ).reference
    bytes&= 255
    if value.first != 255 or value.second != 42 { abort }
    value.first = 7
    if bytes&!= 7 { abort }
    readonly ::= trusted_reinterpret_reference#(.from: Record, .to: UInt8)(
        .base = &value
    ).reference
    if readonly&!= 7 { abort }
    buffer :: [8]UInt8 = zeroed#(.t: [8]UInt8)()
    index :: UIntNative = 0
    while index < 8 {
        source_byte ::= trusted_reference_offset#(.t: UInt8)(
            .base = readonly, .elements = index
        ).reference
        buffer[index] = source_byte&
        index = index + 1
    }
    restored :: Record = (.first = 0, .second = 0)
    restored_bytes ::= trusted_mutable_reinterpret_reference#(.from: Record, .to: UInt8)(
        .base = $&restored
    ).reference
    index = 0
    while index < 8 {
        destination_byte ::= trusted_mutable_reference_offset#(.t: UInt8)(
            .base = restored_bytes, .elements = index
        ).reference
        destination_byte&= buffer[index]
        index = index + 1
    }
    if restored.first != 7 or restored.second != 42 { abort }
    result = 42
}

main := () -> (.status_code: Int32 = 0) {
    compiled ::= #run exercise()
    if compiled != 42 { abort }
    #if exercise() == 42 {
        status_code = exercise()
    } else {
        abort
    }
}
