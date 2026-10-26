text := () -> (.result: StringView) {
    result = "hello"
}

main := () -> (.status_code: Int32 = 0) {
    value ::= text()
    if byte_length(&value).count != 5 { abort }
    first ::= byte_data(.text = value).reference
    last ::= trusted_reference_offset<.t: UInt8>(.base = first, .elements = 4).reference
    if first&!= 104 { abort }
    if last&!= 111 { abort }
    empty: StringView = ""
    if byte_length(&empty).count != 0 { abort }
    unicode: StringView = "ñ€"
    if byte_length(&unicode).count != 5 { abort }
    status_code = 42
}
