Terminal#(.stdin_stream: Type, .stdout_stream: Type, .stderr_stream: Type) : Type = (
    .stdin  : &stdin_stream
    .stdout : $&stdout_stream
    .stderr : $&stderr_stream
)

write_stdout(
    .stdout: $&OutputStream#(.text: String) = #reach stdout, terminal.stdout, system.terminal.stdout,
    .text: String,
) -> () := {
    write(.self = stdout, .text = text)
}

flush_stdout(
    .stdout: $&OutputStream#(.text: String) = #reach stdout, terminal.stdout, system.terminal.stdout,
) -> () := {
    flush(.self = stdout)
}

write_stderr(
    .stderr: $&OutputStream#(.text: String) = #reach stderr, terminal.stderr, system.terminal.stderr,
    .text: String,
) -> () := {
    write(.self = stderr, .text = text)
}

flush_stderr(
    .stderr: $&OutputStream#(.text: String) = #reach stderr, terminal.stderr, system.terminal.stderr,
) -> () := {
    flush(.self = stderr)
}

read_stdin(
    .stdin: $&InputStream#(.line: String) = #reach stdin, terminal.stdin, system.terminal.stdin,
) -> (.line: String) := {
    line = read_line(.self = stdin)
}

Arguments : Type = ()
