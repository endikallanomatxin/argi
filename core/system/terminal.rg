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
    .buffer: $&String,
    .stdin: $&Reader = #reach stdin, terminal.stdin_buffered_reader, system.terminal.stdin_buffered_reader,
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

read_line(
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .stdin: $&Reader = #reach stdin, terminal.stdin_buffered_reader, system.terminal.stdin_buffered_reader,
) -> (.text: String) := {
    initial_capacity :: UIntNative = 16
    text = String(.allocator = allocator, .capacity = initial_capacity)

    while 1 == 1 {
        next ::= read_byte(.self = stdin)
        if is(.value = next, .variant = ..end) {
            return
        }

        payload ::= next..ok
        if payload.byte == 10 {
            return
        }

        if has_space(.self = &text).ok {
        } else {
            current_capacity ::= capacity(.self = &text).value
            next_capacity ::= current_capacity * 2
            ensure_capacity(.self = $&text, .capacity = next_capacity, .allocator = allocator)
        }

        push_byte(.self = $&text, .byte = payload.byte)
    }
}

print(
    .value: String,
    .stdout: $&Writer = #reach stdout, terminal.stdout_buffered_writer, system.terminal.stdout_buffered_writer,
) -> () := {
    i :: UIntNative = 0
    while i < value.length {
        write_byte(.self = stdout, .byte = bytes_get(.string = &value, .index = i).byte)
        i = i + 1
    }
    flush(.self = stdout)
}

print(
    .value: &Char,
    .stdout: $&Writer = #reach stdout, terminal.stdout_buffered_writer, system.terminal.stdout_buffered_writer,
) -> () := {
    i :: UIntNative = 0
    while 1 == 1 {
        addr :: UIntNative = cast#(.to: UIntNative)(.value = value) + i
        ptr : &UInt8 = cast#(.to: &UInt8)(.value = addr)
        if ptr& == 0 {
            break
        }

        write_byte(.self = stdout, .byte = ptr&)
        i = i + 1
    }

    flush(.self = stdout)
}

flush(
    .stdout: $&Writer = #reach stdout, terminal.stdout_buffered_writer, system.terminal.stdout_buffered_writer,
) -> () := {
    flush(.self = stdout)
}

print_error(
    .value: String,
    .stderr: $&Writer = #reach stderr, terminal.stderr_buffered_writer, system.terminal.stderr_buffered_writer,
) -> () := {
    i :: UIntNative = 0
    while i < value.length {
        write_byte(.self = stderr, .byte = bytes_get(.string = &value, .index = i).byte)
        i = i + 1
    }
}

flush_error(
    .stderr: $&Writer = #reach stderr, terminal.stderr_buffered_writer, system.terminal.stderr_buffered_writer,
) -> () := {
    flush(.self = stderr)
}
