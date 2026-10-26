logging := import ("logging")

escape := () -> (.result: logging.FileLogger<ByteWriter>) {
    bytes ::= zeroed<[64]UInt8>()
    writer ::= ByteWriter(.bytes = view(.self = $&bytes))
    result = logging.FileLogger<ByteWriter>(.writer = $&writer)
}

main := () -> () { logger ::= escape() }
