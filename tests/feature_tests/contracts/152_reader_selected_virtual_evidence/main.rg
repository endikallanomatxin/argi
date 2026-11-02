consume := #(.Stream: Type: Reader#(Stream)) (.stream: $&Stream) -> (.byte: UInt8) {

    match unwrap_or_abort(.value = Reader#().read_byte(stream)) {
        ..end { abort }
        ..ok value { byte = value }
    }
}

main := () -> (.status_code: Int32 = 0) {

    bytes: [4]UInt8 = (42, 7, 8, 9)
    reader ::= ByteReader(.bytes = view(&bytes))
    if consume($&reader).byte != 42 { abort }
    match read_byte($&reader) {
        ..error _ { abort }
        ..ok next { match next { ..end { abort } ..ok byte { if byte != 7 { abort } } } }
    }
    erased ::= to_virtual#(.contract: Reader)(.value = $&reader)
    match Reader#().read_byte($&erased) {
        ..error _ { abort }
        ..ok next { match next { ..end { abort } ..ok byte { if byte != 8 { abort } } } }
    }
    match read_byte($&erased) {
        ..error _ { abort }
        ..ok next { match next { ..end { abort } ..ok byte { if byte != 9 { abort } } } }
    }
}
