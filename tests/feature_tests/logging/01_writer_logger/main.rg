logging := import ("logging")

run_main(.system: System) -> !Void = ..ok Void() := {
    storage ::= zeroed#(.t: [64]UInt8)()
    writer ::= ByteWriter(.bytes = view(.self = $&storage))
    logger ::= logging.FileLogger#(.t: ByteWriter)(.writer = $&writer)
    logging.Logger#().log(.self = $&logger, .level = ..debug, .message = "discard")!
    logging.Logger#().log(.self = $&logger, .level = ..info, .message = "hello\nworld")!
    logging.flush(.self = $&logger)!
    text_storage ::= unwrap_or_abort(
        .value = string_from_bytes(
            .bytes = unwrap_or_abort(
                .value = slice(&view(&storage), .start = 0, .count = 19)
            )
            .allocator = system.page_allocator
        )
    )
    text ::= view(&text_storage)
    if text != "INFO: hello\\nworld\n" { abort }
}

main#(.WriterType: Type: Writer#(WriterType))(
    .system: System, .writer: $&WriterType = reach writer
) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
