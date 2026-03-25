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

deinit(
    .self: $&StdIn,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> () := {
    deinit(.self = $&self&.reader, .allocator = allocator)
    close(.self = $&self&.file)
}

init(
    .p: $&StdOut,
    .allocator: $&CAllocator,
) -> () := {
    init_stdout_handle(.p = $&p&.file)
    p&.writer = FileWriter(.allocator = allocator, .file = $&p&.file, .capacity = 256)
}

deinit(
    .self: $&StdOut,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> () := {
    deinit(.self = $&self&.writer, .allocator = allocator)
    close(.self = $&self&.file)
}

init(
    .p: $&StdErr,
    .allocator: $&CAllocator,
) -> () := {
    init_stderr_handle(.p = $&p&.file)
    p&.writer = FileWriter(.allocator = allocator, .file = $&p&.file, .capacity = 256)
}

deinit(
    .self: $&StdErr,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> () := {
    deinit(.self = $&self&.writer, .allocator = allocator)
    close(.self = $&self&.file)
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

deinit(
    .self: $&Terminal,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> () := {
    deinit(.self = self&.stdin, .allocator = allocator)
    deinit(.self = self&.stdout, .allocator = allocator)
    deinit(.self = self&.stderr, .allocator = allocator)
}

read_line(
    .self: $&StdIn,
    .buffer: $&TextBuffer,
) -> () := {
    clear(.self = buffer)

    while 1 == 1 {
        if has_space(.self = buffer).ok {
        } else {
            break
        }

        next ::= read_byte(.self = $&self&.reader)
        if is(.value = next, .variant = ..end) {
            break
        }

        payload ::= next..ok
        if payload.byte == 10 {
            break
        }

        push_byte(.self = buffer, .byte = payload.byte)
    }
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

print_text_buffer(
    .stdout: $&Writer = #reach stdout, terminal.stdout, system.terminal.stdout,
    .buffer: &TextBuffer,
) -> () := {
    write_text_buffer(.writer = stdout, .buffer = buffer)
}

print_line_text_buffer(
    .stdout: $&Writer = #reach stdout, terminal.stdout, system.terminal.stdout,
    .buffer: &TextBuffer,
) -> () := {
    write_line_text_buffer(.writer = stdout, .buffer = buffer)
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

print_error_text_buffer(
    .stderr: $&Writer = #reach stderr, terminal.stderr, system.terminal.stderr,
    .buffer: &TextBuffer,
) -> () := {
    write_text_buffer(.writer = stderr, .buffer = buffer)
}

print_error_line_text_buffer(
    .stderr: $&Writer = #reach stderr, terminal.stderr, system.terminal.stderr,
    .buffer: &TextBuffer,
) -> () := {
    write_line_text_buffer(.writer = stderr, .buffer = buffer)
}

flush_error(
    .stderr: $&Writer = #reach stderr, terminal.stderr, system.terminal.stderr,
) -> () := {
    flush(.self = stderr)
}
