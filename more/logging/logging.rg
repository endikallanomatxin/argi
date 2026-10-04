Logger: Abstract = (
    debug(.msg: String) -> ()
    info(.msg: String) -> ()
    warn(.msg: String) -> ()
    error(.msg: String) -> ()
)

FileLogger: Type = (
    .file : $&Writer
)

FileLogger init(.file: $&Writer) -> (.out: FileLogger) := {
    out = (.file = file)
}

StdLogger: Type = (
    .writer       : $&Writer
    .error_writer : $&Writer
)

StdLogger init(.writer: $&Writer, .error_writer: $&Writer) -> (.out: StdLogger) := {
    out = (.writer = writer, .error_writer = error_writer)
}

LoggerMultiplexer: Type = (
    .loggers : List#(.t: Logger)
)
