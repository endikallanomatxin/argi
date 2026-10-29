logging := import ("logging")

escape := (.error_tracer: $&Virtual#(ErrorTracer)) -> (.result: logging.FileLogger#(ByteWriter)) {
    assume error_tracer
    bytes ::= zeroed#([64]UInt8)()
    writer ::= ByteWriter(.bytes = view(.self = $&bytes))
    result = logging.FileLogger#(ByteWriter)(.writer = $&writer)
}

main := () -> () {
    assume error_tracer ::= $&noop_error_tracer
    logger ::= escape()
}
