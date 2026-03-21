Logger : Abstract = (
    debug(.msg: String) -> ()
    info(.msg: String) -> ()
    warn(.msg: String) -> ()
    error(.msg: String) -> ()
)

FileLogger : Type = (
    .file: $& OutputStream
)

init(.t: Type = FileLogger, .file: OutputStream) -> (.out: FileLogger) := {
    return FileLogger(.file = file)
}

StdLogger : Type = (
    .stdout: $& OutputStream
    .stderr: $& OutputStream
)

init(.t: Type = StdLogger, .stdout: OutputStream, .stderr: OutputStream) -> (.out: StdLogger) := {
    -- TODO: Pensar como eso se puede declarar usando la sintaxis cómoda de init.
    return StdLogger(.stdout = stdout, .stderr = stderr)
}

LoggerMultiplexer : Type = (
    .loggers: List#(.t: Logger)
)
