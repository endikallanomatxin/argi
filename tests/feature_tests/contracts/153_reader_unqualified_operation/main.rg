main := () -> () {
    bytes: [1]UInt8 = (42)
    reader ::= ByteReader(.bytes = view(&bytes))
    read_byte($&reader)
}
