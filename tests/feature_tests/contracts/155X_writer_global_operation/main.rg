main := () -> () {
    bytes: [1]UInt8 = (0)
    writer ::= ByteWriter(.bytes = view($&bytes))
    write_byte($&writer, .byte = 42)
}
