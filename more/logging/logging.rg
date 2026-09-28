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
    .stdout: $&Writer
    .stderr: $&Writer
)

init(.t: Type = StdLogger, .stdout: $&Writer, .stderr: $&Writer) -> (.out: StdLogger) := {
    -- TODO: Consider how to declare this with the convenient init syntax.
    return StdLogger(.stdout = stdout, .stderr = stderr)
}

LoggerMultiplexer : Type = (
    .loggers: List#(.t: Logger)
)
