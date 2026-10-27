main := () -> (.status_code: Int32 = 0) {
    bytes: [1]UInt8 = (42)
    reader ::= ByteReader(.bytes = view(&bytes))
    erased ::= to_virtual#(.contract: Reader)(.value = $&reader)
    match read_byte($&erased) {
        ..error _ { abort } ..ok next {
            match next { ..end { abort } ..ok byte { if [byte != 42] { abort } } }
        }
    }
}
