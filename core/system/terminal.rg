TerminalStorage : Type = (
    .stdin_file            : File
    .stdout_file           : File
    .stderr_file           : File
    .stdin_buffered_reader : BufferedReader#(.base_type: File)
    .stdout_buffered_writer: BufferedWriter#(.base_type: File)
    .stderr_buffered_writer: BufferedWriter#(.base_type: File)
)

Terminal : Type = (
    ._storage              : TerminalStorage
    .stdin_file            : $&File
    .stdout_file           : $&File
    .stderr_file           : $&File
    .stdin_buffered_reader : $&BufferedReader#(.base_type: File)
    .stdout_buffered_writer: $&BufferedWriter#(.base_type: File)
    .stderr_buffered_writer: $&BufferedWriter#(.base_type: File)
)

once init(
    .p: $&Terminal,
    .allocator: $&CAllocator = #reach allocator, system.allocator,
) -> () := {
    init_stdin(.p = $&p&._storage.stdin_file)
    init_stdout(.p = $&p&._storage.stdout_file)
    init_stderr(.p = $&p&._storage.stderr_file)

    p&._storage.stdin_buffered_reader = BufferedReader#(.base_type: File)(
        .allocator = allocator,
        .base = $&p&._storage.stdin_file,
        .capacity = 256,
    )
    p&._storage.stdout_buffered_writer = BufferedWriter#(.base_type: File)(
        .allocator = allocator,
        .base = $&p&._storage.stdout_file,
        .capacity = 256,
    )
    p&._storage.stderr_buffered_writer = BufferedWriter#(.base_type: File)(
        .allocator = allocator,
        .base = $&p&._storage.stderr_file,
        .capacity = 256,
    )

    p&.stdin_file = $&p&._storage.stdin_file
    p&.stdout_file = $&p&._storage.stdout_file
    p&.stderr_file = $&p&._storage.stderr_file
    p&.stdin_buffered_reader = $&p&._storage.stdin_buffered_reader
    p&.stdout_buffered_writer = $&p&._storage.stdout_buffered_writer
    p&.stderr_buffered_writer = $&p&._storage.stderr_buffered_writer
}

deinit(
    .self: $&Terminal,
    .allocator: $&CAllocator = #reach allocator, system.allocator,
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
    .stdin: $&Reader = #reach stdin, terminal.stdin_file, system.terminal.stdin_file,
) -> (.result: Errable#(.t: Void, .reasons: (..stream_read_failed))) := {
    clear(.self = buffer)

    while 1 == 1 {
        if has_space(.self = buffer).ok {
        } else {
            break
        }

        next ::= read_byte(.self = stdin)
        if is(.value = next, .variant = ..error) {
            result = ..error(.reason = ..stream_read_failed)
            return
        }

        next_value ::= next..ok.value
        if is(.value = next_value, .variant = ..end) {
            break
        }

        payload ::= next_value..ok
        if payload.byte == 10 {
            break
        }

        push_byte(.self = buffer, .byte = payload.byte)
    }

    result = ..ok(.value = Void())
}

read_line(
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .stdin: $&Reader = #reach stdin, terminal.stdin_file, system.terminal.stdin_file,
) -> (.result: Errable#(.t: ReadLine, .reasons: (..stream_read_failed, ..out_of_memory))) := {
    initial_capacity :: UIntNative = 16
    create_result ::= string_with_capacity(.allocator = allocator, .capacity = initial_capacity)
    if is(.value = create_result, .variant = ..error) {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    line ::= create_result..ok.value

    while 1 == 1 {
        next ::= read_byte(.self = stdin)
        if is(.value = next, .variant = ..error) {
            deinit(.self = $&line, .allocator = allocator)
            result = ..error(.reason = ..stream_read_failed)
            return
        }

        next_value ::= next..ok.value
        if is(.value = next_value, .variant = ..end) {
            if line.length == 0 {
                deinit(.self = $&line, .allocator = allocator)
                result = ..ok(.value = ..end)
                return
            }

            result = ..ok(.value = ..ok(.text = line))
            return
        }

        payload ::= next_value..ok
        if payload.byte == 10 {
            result = ..ok(.value = ..ok(.text = line))
            return
        }

        grew ::= push_byte_growing(.self = $&line, .byte = payload.byte, .allocator = allocator)
        match grew {
            ..ok _ {
            }
            ..error _ {
                deinit(.self = $&line, .allocator = allocator)
                result = ..error(.reason = ..out_of_memory)
                return
            }
        }
    }
}

print(
    .value: String,
    .stdout: $&Writer = #reach stdout, terminal.stdout_file, system.terminal.stdout_file,
) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    i :: UIntNative = 0
    while i < value.length {
        wrote ::= write_byte(.self = stdout, .byte = bytes_get(.string = &value, .index = i).byte)
        match wrote {
            ..ok _ {
            }
            ..error & err {
                if is(.value = err&.reason, .variant = ..stream_write_failed) {
                    result = ..error(.reason = ..stream_write_failed)
                } else {
                    result = ..error(.reason = ..stream_flush_failed)
                }
                return
            }
        }
        i = i + 1
    }
    result = flush(.self = stdout)
}

print(
    .value: StringView,
    .stdout: $&Writer = #reach stdout, terminal.stdout_file, system.terminal.stdout_file,
) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    i :: UIntNative = 0
    while i < value.length {
        wrote ::= write_byte(.self = stdout, .byte = bytes_get(.view = &value, .index = i).byte)
        match wrote {
            ..ok _ {
            }
            ..error & err {
                if is(.value = err&.reason, .variant = ..stream_write_failed) {
                    result = ..error(.reason = ..stream_write_failed)
                } else {
                    result = ..error(.reason = ..stream_flush_failed)
                }
                return
            }
        }
        i = i + 1
    }
    result = flush(.self = stdout)
}

print(
    .value: &StringView,
    .stdout: $&Writer = #reach stdout, terminal.stdout_file, system.terminal.stdout_file,
) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    result = print(.value = value&, .stdout = stdout)
}

print(
    .value: &Char,
    .stdout: $&Writer = #reach stdout, terminal.stdout_file, system.terminal.stdout_file,
) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    i :: UIntNative = 0
    while 1 == 1 {
        addr :: UIntNative = cast#(.to: UIntNative)(.value = value) + i
        ptr : &UInt8 = cast#(.to: &UInt8)(.value = addr)
        if ptr& == 0 {
            break
        }

        wrote ::= write_byte(.self = stdout, .byte = ptr&)
        match wrote {
            ..ok _ {
            }
            ..error & err {
                if is(.value = err&.reason, .variant = ..stream_write_failed) {
                    result = ..error(.reason = ..stream_write_failed)
                } else {
                    result = ..error(.reason = ..stream_flush_failed)
                }
                return
            }
        }
        i = i + 1
    }

    result = flush(.self = stdout)
}

flush(
    .stdout: $&Writer = #reach stdout, terminal.stdout_file, system.terminal.stdout_file,
) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    result = flush(.self = stdout)
}

print_error(
    .value: String,
    .stderr: $&Writer = #reach stderr, terminal.stderr_file, system.terminal.stderr_file,
) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    i :: UIntNative = 0
    while i < value.length {
        wrote ::= write_byte(.self = stderr, .byte = bytes_get(.string = &value, .index = i).byte)
        match wrote {
            ..ok _ {
            }
            ..error & err {
                if is(.value = err&.reason, .variant = ..stream_write_failed) {
                    result = ..error(.reason = ..stream_write_failed)
                } else {
                    result = ..error(.reason = ..stream_flush_failed)
                }
                return
            }
        }
        i = i + 1
    }

    result = ..ok(.value = Void())
}

print_error(
    .value: StringView,
    .stderr: $&Writer = #reach stderr, terminal.stderr_file, system.terminal.stderr_file,
) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    i :: UIntNative = 0
    while i < value.length {
        wrote ::= write_byte(.self = stderr, .byte = bytes_get(.view = &value, .index = i).byte)
        match wrote {
            ..ok _ {
            }
            ..error & err {
                if is(.value = err&.reason, .variant = ..stream_write_failed) {
                    result = ..error(.reason = ..stream_write_failed)
                } else {
                    result = ..error(.reason = ..stream_flush_failed)
                }
                return
            }
        }
        i = i + 1
    }

    result = ..ok(.value = Void())
}

print_error(
    .value: &StringView,
    .stderr: $&Writer = #reach stderr, terminal.stderr_file, system.terminal.stderr_file,
) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    result = print_error(.value = value&, .stderr = stderr)
}

flush_error(
    .stderr: $&Writer = #reach stderr, terminal.stderr_file, system.terminal.stderr_file,
) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    result = flush(.self = stderr)
}
