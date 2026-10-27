LogLevel: Type = (..debug, ..info, ..warning, ..error)

implement ImplicitlyCopyable#(LogLevel) ()

LogReasons: Type = (..stream_write_failed, ..stream_flush_failed)

Logger#(.Value: Type): Contract = (
    .log : (.self: $&Value, .level: LogLevel, .message: StringView) -> (
        .result : Errable#(Void, LogReasons)
    ) where {}
)

_rank := (.level: LogLevel) -> (.value: Int32) {
    match level {
        ..debug { value = 0 } ..info { value = 1 } ..warning { value = 2 } ..error {
            value = 3
        }
    }
}

_prefix := (.level: LogLevel) -> (.text: StringView) {
    match level {
        ..debug { text = "DEBUG" } ..info { text = "INFO" } ..warning { text = "WARN" } ..error {
            text = "ERROR"
        }
    }
}

-- Records borrow text and require no allocation. Escape line breaks to keep
-- each record on one line. Writes can fail after a prefix; callers decide
-- whether logging failures should affect their application. Flush is explicit.
_write_record := #(.WriterType: Type: Writer#(WriterType)) (
    .writer: $&WriterType, .level: LogLevel, .message: StringView
) -> (.result: Errable#(Void, LogReasons) = ..ok Void()) {
    write(.self = writer, .value = _prefix(.level = level).text)!
    write(.self = writer, .value = ": ")!
    index :: UIntNative = 0

    while index < byte_length(&message).count {
        byte ::= unwrap_or_abort(.value = bytes_get(.view = &message, .index = index))
        if byte == 10 {
            write(.self = writer, .value = "\\n")!
        } else {
            if byte == 13 {
                write(.self = writer, .value = "\\r")!
            } else {
                Writer#().write_byte(.self = writer, .byte = byte)!
            }
        }
        index = index + 1
    }

    write(.self = writer, .value = "\n")!
}

FileLogger := #(.t: Type: Writer#(t)) (._writer: $&t, .minimum: LogLevel)

implement#(.t: Type: Writer#(t)) Init#(FileLogger#(.t: t)) (
    .init = (.writer: $&t, .minimum: LogLevel = ..info) -> (.result: FileLogger#(.t: t)) {
        result = (._writer = writer, .minimum = minimum)
    }
)

implement#(.t: Type: Writer#(t)) Logger#(FileLogger#(.t: t)) (
    .log = (.self: $&FileLogger#(.t: t), .level: LogLevel, .message: StringView) -> (
        .result : Errable#(Void, LogReasons) = ..ok Void()
    ) {
        if _rank(.level = level).value < _rank(.level = self&.minimum).value { return }
        _write_record(.writer = self&._writer, .level = level, .message = message)!
    }
)

flush := #(.t: Type: Writer#(t)) (.self: $&FileLogger#(.t: t)) -> (
    .result : Errable#(Void, LogReasons) = ..ok Void()
) {
    Writer#().flush(.self = self&._writer)!
}

StdLogger := #(.out: Type: Writer#(out), .err: Type: Writer#(err)) (
    ._out    : $&out,
    ._err    : $&err,
    .minimum : LogLevel
)

implement#(.out: Type: Writer#(out), .err: Type: Writer#(err)) Init#(
    StdLogger#(.out: out, .err: err)
) (
    .init = (.writer: $&out, .error_writer: $&err, .minimum: LogLevel = ..info) -> (
        .result : StdLogger#(.out: out, .err: err)
    ) {
        result = (._out = writer, ._err = error_writer, .minimum = minimum)
    }
)

implement#(.out: Type: Writer#(out), .err: Type: Writer#(err)) Logger#(
    StdLogger#(.out: out, .err: err)
) (
    .log = (.self: $&StdLogger#(.out: out, .err: err), .level: LogLevel, .message: StringView) -> (
        .result : Errable#(Void, LogReasons) = ..ok Void()
    ) {
        if _rank(.level = level).value < _rank(.level = self&.minimum).value { return }
        if _rank(.level = level).value >= 2 {
            _write_record(.writer = self&._err, .level = level, .message = message)!
        } else {
            _write_record(.writer = self&._out, .level = level, .message = message)!
        }
    }
)

NullLogger: Type = ()

implement Logger#(NullLogger) (
    .log = (.self: $&NullLogger, .level: LogLevel, .message: StringView) -> (
        .result : Errable#(Void, LogReasons) = ..ok Void()
    ) {
    }
)
