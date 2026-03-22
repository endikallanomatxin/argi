Terminal#(.stdin_stream: Type, .stdout_stream: Type, .stderr_stream: Type) : Type = (
    .stdin  : &stdin_stream
    .stdout : $&stdout_stream
    .stderr : $&stderr_stream
)

Arguments : Type = ()
