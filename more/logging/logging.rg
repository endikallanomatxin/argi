Logger : Abstract = [
    $debug(msg: String)
    $info (msg: String)
    $warn (msg: String)
    $error(msg: String)
]

FileLogger : struct = [
    .file: $& OutputStream
]

init(t : Type == FileLogger, file: OutputStream) := FileLogger {
    return FileLogger(file: file)
}

StdLogger : struct = [
    .stdout: $& OutputStream
    .stderr: $& OutputStream
]

init(t : Type == StdLogger, stdout: OutputStream, stderr: OutputStream) := StdLogger {
    -- TODO: Pensar como eso se puede declarar usando la sintaxis cómoda de init.
    return StdLogger(stdout: stdout, stderr: stderr)
}

LoggerMultiplexer : struct = [
    loggers: List<Logger>
]
