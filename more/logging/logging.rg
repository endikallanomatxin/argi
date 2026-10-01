Logger : Abstract = (
    debug(.msg: String) -> ()
    info(.msg: String) -> ()
    warn(.msg: String) -> ()
    error(.msg: String) -> ()
)

FileLogger : Type = (
    .file: $&Writer
)

init(.t: Type = FileLogger, .file: $&Writer) -> (.out: FileLogger) := {
    return FileLogger(.file = file)
}

StdLogger : Type = (
    .writer: $&Writer
    .error_writer: $&Writer
)

init(.t: Type = StdLogger, .writer: $&Writer, .error_writer: $&Writer) -> (.out: StdLogger) := {
    -- TODO: Consider how to declare this with the convenient init syntax.
    return StdLogger(.writer = writer, .error_writer = error_writer)
}

LoggerMultiplexer : Type = (
    .loggers: List#(.t: Logger)
)
