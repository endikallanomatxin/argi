StdIn : Type = (
    .file            : File
    .reader          : FileReader
    .buffered_reader : BufferedReader
)

StdOut : Type = (
    .file            : File
    .writer          : FileWriter
    .buffered_writer : BufferedWriter
)

StdErr : Type = (
    .file            : File
    .writer          : FileWriter
    .buffered_writer : BufferedWriter
)

init(
    .p: $&StdIn,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> () := {
    p&.file = File(.descriptor = 0, .kind = ..stdin)
    p&.reader = FileReader(.file = $&p&.file)
    p&.buffered_reader = BufferedReader(.allocator = allocator, .reader = $&p&.reader, .capacity = 256)
}

init(
    .p: $&StdOut,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> () := {
    p&.file = File(.descriptor = 1, .kind = ..stdout)
    p&.writer = FileWriter(.file = $&p&.file)
    p&.buffered_writer = BufferedWriter(.allocator = allocator, .writer = $&p&.writer, .capacity = 256)
}

init(
    .p: $&StdErr,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> () := {
    p&.file = File(.descriptor = 2, .kind = ..stderr)
    p&.writer = FileWriter(.file = $&p&.file)
    p&.buffered_writer = BufferedWriter(.allocator = allocator, .writer = $&p&.writer, .capacity = 256)
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
    next ::= read_byte(.self = $&self&.buffered_reader)
    result = next
}

write_byte(.self: $&StdOut, .byte: UInt8) -> () := {
    write_byte(.self = self&.buffered_writer.writer, .byte = byte)
}

flush(.self: $&StdOut) -> () := {
    flush(.self = $&self&.buffered_writer)
}

write_byte(.self: $&StdErr, .byte: UInt8) -> () := {
    write_byte(.self = self&.buffered_writer.writer, .byte = byte)
}

flush(.self: $&StdErr) -> () := {
    flush(.self = $&self&.buffered_writer)
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
