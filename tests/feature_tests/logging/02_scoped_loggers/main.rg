logging := import ("logging")

check := (.system: System) -> (.result: Errable<Void, logging.LogReasons> = ..ok Void()) {
    output_bytes ::= zeroed<[64]UInt8>()
    error_bytes ::= zeroed<[64]UInt8>()
    output ::= ByteWriter(.bytes = view(.self = $&output_bytes))
    errors ::= ByteWriter(.bytes = view(.self = $&error_bytes))
    logger ::= logging.StdLogger<ByteWriter, ByteWriter>(
        .writer = $&output, .error_writer = $&errors
    )
    logging.Logger<>.log(.self = $&logger, .level = ..info, .message = "ready")!
    logging.Logger<>.log(.self = $&logger, .level = ..warning, .message = "problem")!
    output_text_storage ::= unwrap_or_abort(
        .value = string_from_bytes(
            .bytes = unwrap_or_abort(
                .value = slice(&view(&output_bytes), .start = 0, .count = 12)
            )
            .allocator = system.page_allocator
        )
    )
    output_text ::= view(&output_text_storage)
    error_text_storage ::= unwrap_or_abort(
        .value = string_from_bytes(
            .bytes = unwrap_or_abort(
                .value = slice(&view(&error_bytes), .start = 0, .count = 14)
            )
            .allocator = system.page_allocator
        )
    )
    error_text ::= view(&error_text_storage)
    if output_text != "INFO: ready\n" or error_text != "WARN: problem\n" { abort }
    erased ::= to_virtual<.contract: logging.Logger>(.value = $&logger)
    logging.Logger<>.log(.self = $&erased, .level = ..debug, .message = "discard")!
    null_logger ::= logging.NullLogger()
    logging.Logger<>.log(.self = $&null_logger, .level = ..error, .message = "ignored")!
}

main := (.system: System) -> (.status_code: Int32 = 1) {
    assume writer ::= $&system.terminal&.stderr
    check(.system = system)!!!
    status_code = 0
}
