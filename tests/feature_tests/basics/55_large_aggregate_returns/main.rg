BufferSource : Abstract = (read(.self: &Self) -> (.bytes: [65536]UInt8))
Source : Type = ()
Source implements BufferSource

read(.self: &Source) -> (.bytes: [65536]UInt8) := {
    bytes = zeroed#(.t: [65536]UInt8)()
    bytes[65535] = 7
}

multiple() -> (.bytes: [65536]UInt8, .marker: Int32) := {
    bytes = zeroed#(.t: [65536]UInt8)()
    bytes[0] = 9
    marker = 42
}

check(.value: UInt8, .expected: UInt8) -> (.status: Int32 = 0) := {
    if value != expected { status = 1 }
}

main() -> (.status_code: Int32 = 0) := {
    bytes ::= zeroed#(.t: [65536]UInt8)()
    status_code = check(bytes[0], 0) + check(bytes[65535], 0)
    values ::= multiple()
    status_code = status_code + check(values.bytes[0], 9) + check(values.bytes[65535], 0)
    source ::= Source()
    handle :: Virtual#(.abstract: BufferSource) = to_virtual(&source)
    from_virtual ::= read(.self = &handle)
    status_code = status_code + check(from_virtual[0], 0) + check(from_virtual[65535], 7)
}
