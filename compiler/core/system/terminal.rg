Terminal#(.stdin_stream: Type, .stdout_stream: Type, .stderr_stream: Type) : Type = (
    .stdin  : $&stdin_stream
    .stdout : $&stdout_stream
    .stderr : $&stderr_stream
)

print(
    .stdout: $&OutputStream#(.text: String) = #reach stdout, terminal.stdout, system.terminal.stdout,
    .text: String,
) -> () := {
    write(.self = stdout, .text = text)
}

flush(
    .stdout: $&OutputStream#(.text: String) = #reach stdout, terminal.stdout, system.terminal.stdout,
) -> () := {
    flush(.self = stdout)
}

print_error(
    .stderr: $&OutputStream#(.text: String) = #reach stderr, terminal.stderr, system.terminal.stderr,
    .text: String,
) -> () := {
    write(.self = stderr, .text = text)
}

flush_error(
    .stderr: $&OutputStream#(.text: String) = #reach stderr, terminal.stderr, system.terminal.stderr,
) -> () := {
    flush(.self = stderr)
}

Arguments : Type = ()
