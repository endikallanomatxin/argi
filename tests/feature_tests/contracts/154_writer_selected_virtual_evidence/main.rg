send := #(.Stream: Type: Writer#(Stream)) (.stream: $&Stream, .byte: UInt8) -> () {

    unwrap_or_abort(Writer#().write_byte(stream, .byte = byte))
}

main := () -> (.status_code: Int32 = 0) {

    bytes: [3]UInt8 = (0, 0, 0)
    writer ::= ByteWriter(.bytes = view($&bytes))
    send($&writer, .byte = 42)
    unwrap_or_abort(write_byte($&writer, .byte = 9))
    erased ::= to_virtual#(.contract: Writer)(.value = $&writer)
    unwrap_or_abort(Writer#().write_byte($&erased, .byte = 7))
    unwrap_or_abort(Writer#().flush($&erased))
    if bytes[0] != 42 or bytes[1] != 9 or bytes[2] != 7 { abort }
}
