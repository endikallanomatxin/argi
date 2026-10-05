LogLevel: Type = (..debug, ..info, ..warning, ..error)

LogLevel implements ImplicitlyCopyable

LogReasons: Type = (..stream_write_failed, ..stream_flush_failed)

Logger: Abstract = (
    log(.self: $&Self, .level: LogLevel, .message: StringView) -> (
        .result : Errable#(Void, LogReasons)
    )
)

_rank(.level: LogLevel) -> (.value: Int32) := {
    match level {
        ..debug { value = 0 } ..info { value = 1 } ..warning { value = 2 } ..error { value = 3 }
    }
}

_prefix(.level: LogLevel) -> (.text: StringView) := {
    match level {
        ..debug { text = "DEBUG" } ..info { text = "INFO" } ..warning { text = "WARN" } ..error {
            text = "ERROR"
        }
    }
}

-- Records borrow text and require no allocation. Escape line breaks to keep
-- each record on one line. Writes can fail after a prefix; callers decide
-- whether logging failures should affect their application. Flush is explicit.
_write_record(
        .writer  : $&Writer,
        .level   : LogLevel,
        .message : StringView
    ) -> (
        .result : Errable#(Void, LogReasons) = ..ok Void()
    ) := {
    write(.self = writer, .text = _prefix(.level = level).text)!
    write(.self = writer, .text = ": ")!
    index :: UIntNative = 0

    while index < message.length {
        byte ::= bytes_get(.view = &message, .index = index).byte
        if byte == 10 { write(.self = writer, .text = "\\n")! } else {
            if byte == 13 { write(.self = writer, .text = "\\r")! } else {
                write_byte(.self = writer, .byte = byte)!
            }
        }
        index = index + 1
    }

    write(.self = writer, .text = "\n")!
}

FileLogger#(.t: Type: Writer): Type = (._writer: $&t, .minimum: LogLevel)

FileLogger#(.t: Type: Writer) implements Logger

FileLogger init#(
        .t : Type: Writer
    )(
        .writer  : $&t,
        .minimum : LogLevel = ..info
    ) -> (
        .result : FileLogger#(.t: t)
    ) := { result = (._writer = writer, .minimum = minimum) }

log#(
        .t : Type: Writer
    )(
        .self    : $&FileLogger#(.t: t),
        .level   : LogLevel,
        .message : StringView
    ) -> (
        .result : Errable#(Void, LogReasons) = ..ok Void()
    ) := {
    if _rank(.level = level).value < _rank(.level = self&.minimum).value { return }
    _write_record(.writer = self&._writer, .level = level, .message = message)!
}

flush#(
        .t : Type: Writer
    )(
        .self : $&FileLogger#(.t: t)
    ) -> (
        .result : Errable#(Void, LogReasons)
    ) := { result = flush(.self = self&._writer) }

StdLogger#(.out: Type: Writer, .err: Type: Writer): Type = (
    ._out    : $&out,
    ._err    : $&err,
    .minimum : LogLevel
)

StdLogger#(.out: Type: Writer, .err: Type: Writer) implements Logger

StdLogger init#(
        .out : Type: Writer,
        .err : Type: Writer
    )(
        .writer       : $&out,
        .error_writer : $&err,
        .minimum      : LogLevel = ..info
    ) -> (
        .result : StdLogger#(.out: out, .err: err)
    ) := { result = (._out = writer, ._err = error_writer, .minimum = minimum) }

log#(
        .out : Type: Writer,
        .err : Type: Writer
    )(
        .self    : $&StdLogger#(.out: out, .err: err),
        .level   : LogLevel,
        .message : StringView
    ) -> (
        .result : Errable#(Void, LogReasons) = ..ok Void()
    ) := {
    if _rank(.level = level).value < _rank(.level = self&.minimum).value { return }
    if _rank(.level = level).value >= 2 {
        _write_record(.writer = self&._err, .level = level, .message = message)!
    } else { _write_record(.writer = self&._out, .level = level, .message = message)! }
}

NullLogger: Type = ()

NullLogger implements Logger

log(
        .self    : $&NullLogger,
        .level   : LogLevel,
        .message : StringView
    ) -> (
        .result : Errable#(Void, LogReasons) = ..ok Void()
    ) := {}
