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
    allocation_size :: UIntNative = initial_capacity + 1
    data ::= allocate(.self = allocator, .size = allocation_size)
    if cast#(.to: UIntNative)(.value = data) == 0 {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    line :: String = (
        .allocation = (
            .data = data,
            .size = allocation_size,
        ),
        .length = 0,
    )
    bytes_set(.string = $&line, .index = 0, .value = 0)

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

        if has_space(.self = &line).ok {
        } else {
            current_capacity ::= capacity(.self = &line).value
            next_capacity ::= current_capacity * 2
            new_allocation_size :: UIntNative = next_capacity + 1
            new_data ::= allocate(.self = allocator, .size = new_allocation_size)
            if cast#(.to: UIntNative)(.value = new_data) == 0 {
                deinit(.self = $&line, .allocator = allocator)
                result = ..error(.reason = ..out_of_memory)
                return
            }

            memcpy(
                .dst = cast#(.to: $&Any)(.value = cast#(.to: UIntNative)(.value = new_data)),
                .src = cast#(.to: &Any)(.value = cast#(.to: UIntNative)(.value = line.allocation.data)),
                .n = line.length + 1,
            )

            deallocate(.self = allocator, .data = line.allocation.data, .size = line.allocation.size)
            line = (
                .allocation = (
                    .data = new_data,
                    .size = new_allocation_size,
                ),
                .length = line.length,
            )
        }

        line_length ::= line.length
        bytes_set(.string = $&line, .index = line_length, .value = payload.byte)
        line = (
            .allocation = line.allocation,
            .length = line_length + 1,
        )
        next_length ::= line.length
        bytes_set(.string = $&line, .index = next_length, .value = 0)
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
            ..ok(_) {
            }
            ..error(& err) {
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
            ..ok(_) {
            }
            ..error(& err) {
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
            ..ok(_) {
            }
            ..error(& err) {
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

flush_error(
    .stderr: $&Writer = #reach stderr, terminal.stderr_file, system.terminal.stderr_file,
) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    result = flush(.self = stderr)
}
