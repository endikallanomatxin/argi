StdIn : Type = ()
StdOut : Type = ()
StdErr : Type = ()

Terminal : Type = (
    .stdin  : $&StdIn
    .stdout : $&StdOut
    .stderr : $&StdErr
)

init(.p: $&Terminal, .stdin: $&StdIn, .stdout: $&StdOut, .stderr: $&StdErr) -> () := {
    p& = (
        .stdin = stdin,
        .stdout = stdout,
        .stderr = stderr
    )
}

read_line(
    .self: $&StdIn,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.line: String) := {
    -- TODO: implement real terminal line reading once Char/byte/int casts and
    -- EOF handling are properly modeled in core IO.
    line = String(.allocator = allocator, .length = 0)
}

write(.self: $&StdOut, .text: String) -> () := {
    i :: UIntNative = 0
    while i < text.length {
        putchar(.character = bytes_get(.string = &text, .index = i).byte)
        i = i + 1
    }
}

flush(.self: $&StdOut) -> () := {
}

write(.self: $&StdErr, .text: String) -> () := {
    i :: UIntNative = 0
    while i < text.length {
        putchar(.character = bytes_get(.string = &text, .index = i).byte)
        i = i + 1
    }
}

flush(.self: $&StdErr) -> () := {
}

StdOut implements OutputStream#(.text: String)
StdErr implements OutputStream#(.text: String)

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
