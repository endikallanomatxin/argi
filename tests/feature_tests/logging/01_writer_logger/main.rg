logging := import ("logging")

main() -> !Void = ..ok Void() := {
    storage ::= zeroed#(.t: [64]UInt8)()
    writer ::= ByteWriter(.bytes = view(.array = $&storage))
    logger ::= logging.FileLogger#(.t: ByteWriter)(.writer = $&writer)
    logging.log(.self = $&logger, .level = ..debug, .message = "discard")!
    logging.log(.self = $&logger, .level = ..info, .message = "hello\nworld")!
    logging.flush(.self = $&logger)!
    text: StringView = (.data = &storage[0], .length = 19)
    if text != "INFO: hello\\nworld\n" { abort }
}
