Terminal : Type = (
    .stdin_file            : $&File
    .stdout_file           : $&File
    .stderr_file           : $&File
    .stdin_buffered_reader : $&BufferedReader#(.base_type: File)
    .stdout_buffered_writer: $&BufferedWriter#(.base_type: File)
    .stderr_buffered_writer: $&BufferedWriter#(.base_type: File)
)

once init(
    .p: $&Terminal,
    .stdin_file: $&File,
    .stdout_file: $&File,
    .stderr_file: $&File,
    .stdin_buffered_reader: $&BufferedReader#(.base_type: File),
    .stdout_buffered_writer: $&BufferedWriter#(.base_type: File),
    .stderr_buffered_writer: $&BufferedWriter#(.base_type: File),
) -> () := {
    p& = (
        .stdin_file = stdin_file,
        .stdout_file = stdout_file,
        .stderr_file = stderr_file,
        .stdin_buffered_reader = stdin_buffered_reader,
        .stdout_buffered_writer = stdout_buffered_writer,
        .stderr_buffered_writer = stderr_buffered_writer,
    )
}

deinit(
    .self: $&Terminal,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> () := {
    deinit(.self = self&.stdin_buffered_reader, .allocator = allocator)
    deinit(.self = self&.stdout_buffered_writer, .allocator = allocator)
    deinit(.self = self&.stderr_buffered_writer, .allocator = allocator)
    close(.self = self&.stdin_file)
    close(.self = self&.stdout_file)
    close(.self = self&.stderr_file)
}

read_line_into_buffer(
    .stdin: $&Reader = #reach stdin, terminal.stdin_buffered_reader, system.terminal.stdin_buffered_reader,
    .buffer: $&TextBuffer,
) -> () := {
    clear(.self = buffer)

    while 1 == 1 {
        if has_space(.self = buffer).ok {
        } else {
            break
        }

        next ::= read_byte(.self = stdin)
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

print(
    .stdout: $&Writer = #reach stdout, terminal.stdout_buffered_writer, system.terminal.stdout_buffered_writer,
    .text: String,
) -> () := {
    write(.self = stdout, .text = text)
}

print_text_buffer(
    .stdout: $&Writer = #reach stdout, terminal.stdout_buffered_writer, system.terminal.stdout_buffered_writer,
    .buffer: &TextBuffer,
) -> () := {
    write_text_buffer(.writer = stdout, .buffer = buffer)
}

print_line_text_buffer(
    .stdout: $&Writer = #reach stdout, terminal.stdout_buffered_writer, system.terminal.stdout_buffered_writer,
    .buffer: &TextBuffer,
) -> () := {
    write_line_text_buffer(.writer = stdout, .buffer = buffer)
}

flush(
    .stdout: $&Writer = #reach stdout, terminal.stdout_buffered_writer, system.terminal.stdout_buffered_writer,
) -> () := {
    flush(.self = stdout)
}

print_error(
    .stderr: $&Writer = #reach stderr, terminal.stderr_buffered_writer, system.terminal.stderr_buffered_writer,
    .text: String,
) -> () := {
    write(.self = stderr, .text = text)
}

print_error_text_buffer(
    .stderr: $&Writer = #reach stderr, terminal.stderr_buffered_writer, system.terminal.stderr_buffered_writer,
    .buffer: &TextBuffer,
) -> () := {
    write_text_buffer(.writer = stderr, .buffer = buffer)
}

print_error_line_text_buffer(
    .stderr: $&Writer = #reach stderr, terminal.stderr_buffered_writer, system.terminal.stderr_buffered_writer,
    .buffer: &TextBuffer,
) -> () := {
    write_line_text_buffer(.writer = stderr, .buffer = buffer)
}

flush_error(
    .stderr: $&Writer = #reach stderr, terminal.stderr_buffered_writer, system.terminal.stderr_buffered_writer,
) -> () := {
    flush(.self = stderr)
}
