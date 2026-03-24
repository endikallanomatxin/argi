init_stdin_handle(.p: $&File) -> () := {
    init_stdin(.p = p)
}

init_stdout_handle(.p: $&File) -> () := {
    init_stdout(.p = p)
}

init_stderr_handle(.p: $&File) -> () := {
    init_stderr(.p = p)
}

StdIn : Type = (
    .file   : File
    .reader : FileReader
)

StdOut : Type = (
    .file   : File
    .writer : FileWriter
)

StdErr : Type = (
    .file   : File
    .writer : FileWriter
)

init(
    .p: $&StdIn,
    .allocator: $&CAllocator,
) -> () := {
    init_stdin_handle(.p = $&p&.file)
    p&.reader = FileReader(.allocator = allocator, .file = $&p&.file, .capacity = 256)
}

init(
    .p: $&StdOut,
    .allocator: $&CAllocator,
) -> () := {
    init_stdout_handle(.p = $&p&.file)
    p&.writer = FileWriter(.allocator = allocator, .file = $&p&.file, .capacity = 256)
}

init(
    .p: $&StdErr,
    .allocator: $&CAllocator,
) -> () := {
    init_stderr_handle(.p = $&p&.file)
    p&.writer = FileWriter(.allocator = allocator, .file = $&p&.file, .capacity = 256)
}

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
    -- text ownership are settled on top of the lower-level Reader/File layers.
    _ ::= allocator
    line = String(.allocator = allocator, .length = 0)
}

read_byte(.self: $&StdIn) -> (.result: ReadByte) := {
    next ::= read_byte(.self = $&self&.reader)
    result = next
}

write_byte(.self: $&StdOut, .byte: UInt8) -> () := {
    write_byte(.self = $&self&.writer, .byte = byte)
}

flush(.self: $&StdOut) -> () := {
    flush(.self = $&self&.writer)
}

write_byte(.self: $&StdErr, .byte: UInt8) -> () := {
    write_byte(.self = $&self&.writer, .byte = byte)
}

flush(.self: $&StdErr) -> () := {
    flush(.self = $&self&.writer)
}

StdIn implements Reader
StdOut implements Writer
StdErr implements Writer

print(
    .stdout: $&Writer = #reach stdout, terminal.stdout, system.terminal.stdout,
    .text: String,
) -> () := {
    write(.self = stdout, .text = text)
}

flush(
    .stdout: $&Writer = #reach stdout, terminal.stdout, system.terminal.stdout,
) -> () := {
    flush(.self = stdout)
}

print_error(
    .stderr: $&Writer = #reach stderr, terminal.stderr, system.terminal.stderr,
    .text: String,
) -> () := {
    write(.self = stderr, .text = text)
}

flush_error(
    .stderr: $&Writer = #reach stderr, terminal.stderr, system.terminal.stderr,
) -> () := {
    flush(.self = stderr)
}
