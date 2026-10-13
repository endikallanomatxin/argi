logging := import("logging")
check := () -> (.result: Errable#(Void, logging.LogReasons) = ..ok Void()) {
    output_bytes ::= zeroed#([64]UInt8)()
    error_bytes ::= zeroed#([64]UInt8)()
    output ::= ByteWriter(.bytes = view(.array = $&output_bytes))
    errors ::= ByteWriter(.bytes = view(.array = $&error_bytes))
    logger ::= logging.StdLogger#(ByteWriter, ByteWriter)(.writer = $&output, .error_writer = $&errors)
    logging.Logger#().log(.self = $&logger, .level = ..info, .message = "ready")!
    logging.Logger#().log(.self = $&logger, .level = ..warning, .message = "problem")!
    output_text: StringView = (.data = &output_bytes[0], .length = 12)
    error_text: StringView = (.data = &error_bytes[0], .length = 14)
    if output_text != "INFO: ready\n" or error_text != "WARN: problem\n" { abort }
    erased ::= to_virtual#(.contract: logging.Logger)(.value = $&logger)
    logging.Logger#().log(.self = $&erased, .level = ..debug, .message = "discard")!
    null_logger ::= logging.NullLogger()
    logging.Logger#().log(.self = $&null_logger, .level = ..error, .message = "ignored")!
}
main := (.writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) { check()!!! status_code = 0 }
