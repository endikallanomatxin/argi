TerminalStorage : Type = (
    .stdin_file   : File
    .stdout_file  : File
    .stderr_file  : File
    .stdin_reader : BufferedReader#(.base_type: File)
    .stdout_writer: BufferedWriter#(.base_type: File)
    .stderr_writer: BufferedWriter#(.base_type: File)
)

Terminal : Type = (
    ._storage      : TerminalStorage
    .stdin_file    : $&File
    .stdout_file   : $&File
    .stderr_file   : $&File
    .stdin_reader  : $&BufferedReader#(.base_type: File)
    .stdout_writer : $&BufferedWriter#(.base_type: File)
    .stderr_writer : $&BufferedWriter#(.base_type: File)
    --
    -- High-level stdio endpoints stay abstract so helpers can depend on
    -- `Reader`/`Writer`, while the raw file handles and concrete buffered
    -- wrappers remain explicit and reachable separately.
    --
    .stdin         : $&Reader
    .stdout        : $&Writer
    .stderr        : $&Writer
)

once init(
    .p: $&Terminal,
    .allocator: $&CAllocator = #reach allocator, system.allocator,
) -> () := {
    init_stdin(.p = $&p&._storage.stdin_file)
    init_stdout(.p = $&p&._storage.stdout_file)
    init_stderr(.p = $&p&._storage.stderr_file)

    p&._storage.stdin_reader = BufferedReader#(.base_type: File)(
        .allocator = allocator,
        .base = $&p&._storage.stdin_file,
        .capacity = 256,
    )
    p&._storage.stdout_writer = BufferedWriter#(.base_type: File)(
        .allocator = allocator,
        .base = $&p&._storage.stdout_file,
        .capacity = 256,
    )
    p&._storage.stderr_writer = BufferedWriter#(.base_type: File)(
        .allocator = allocator,
        .base = $&p&._storage.stderr_file,
        .capacity = 256,
    )

    p&.stdin_file = $&p&._storage.stdin_file
    p&.stdout_file = $&p&._storage.stdout_file
    p&.stderr_file = $&p&._storage.stderr_file
    p&.stdin_reader = $&p&._storage.stdin_reader
    p&.stdout_writer = $&p&._storage.stdout_writer
    p&.stderr_writer = $&p&._storage.stderr_writer
    p&.stdin = $&p&._storage.stdin_reader
    p&.stdout = $&p&._storage.stdout_writer
    p&.stderr = $&p&._storage.stderr_file
}

deinit(
    .self: $&Terminal,
    .allocator: $&CAllocator = #reach allocator, system.allocator,
) -> () := {
    deinit(.self = self&.stdin_reader, .allocator = allocator)
    deinit(.self = self&.stdout_writer, .allocator = allocator)
    deinit(.self = self&.stderr_writer, .allocator = allocator)
    close(.self = self&.stdin_file)
    close(.self = self&.stdout_file)
    close(.self = self&.stderr_file)
}

read_line_into_buffer(
    .buffer: $&String,
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .stdin: $&Reader = #reach stdin, terminal.stdin, system.terminal.stdin,
) -> (.result: Errable#(.t: Void, .reasons: (..stream_read_failed))) := {
    clear(.self = buffer)

    while 1 == 1 {
        if has_space(.self = buffer).ok {
        } else {
            break
        }

        next ::= read_byte(.self = stdin)
        match next {
            ..error _ {
                result = ..error(.reason = ..stream_read_failed)
                return
            }
            ..ok next_value {
                match next_value {
                    ..end {
                        break
                    }
                    ..ok payload {
                        if payload == 10 {
                            break
                        }

                        pushed ::= push_byte(.self = buffer, .byte = payload, .allocator = allocator)
                        match pushed {
                            ..ok _ {
                            }
                            ..error _ {
                                result = ..error(.reason = ..stream_read_failed)
                                return
                            }
                        }
                    }
                }
            }
        }
    }

    result = ..ok Void()
}

read_line(
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .stdin: $&Reader = #reach stdin, terminal.stdin, system.terminal.stdin,
) -> (.result: Errable#(.t: ReadLine, .reasons: (..stream_read_failed, ..out_of_memory))) := {
    --
    -- `read_line()` returns an owning `String`.
    --
    -- The returned bytes are independent from the input stream and remain
    -- valid until the caller `deinit()`s that `String`.
    --
    initial_capacity :: UIntNative = 16
    create_result ::= string_with_capacity(.allocator = allocator, .capacity = initial_capacity)
    line :: String
    match create_result {
        ..ok ~ payload { line = ~payload }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
            return
        }
    }

    line_complete :: Bool = false
    while 1 == 1 {
        next ::= read_byte(.self = stdin)
        match next {
            ..error _ {
                deinit(.self = $&line, .allocator = allocator)
                result = ..error(.reason = ..stream_read_failed)
                return
            }
            ..ok next_value {
                match next_value {
                    ..end {
                        if line.length == 0 {
                            deinit(.self = $&line, .allocator = allocator)
                            result = ..ok ..end
                            return
                        }

                        line_complete = true
                        break
                    }
                    ..ok payload {
                        if payload == 10 {
                            line_complete = true
                            break
                        }

                        grew ::= push_byte(.self = $&line, .byte = payload, .allocator = allocator)
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
            }
        }
    }
    if line_complete {
        result = ..ok ..ok ~line
    }
}

print(
    .value: StringView,
    .stdout: $&Writer = #reach stdout, terminal.stdout, system.terminal.stdout,
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

flush(
    .stdout: $&Writer = #reach stdout, terminal.stdout, system.terminal.stdout,
) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    result = flush(.self = stdout)
}

print_error(
    .value: StringView,
    .stderr: $&Writer = #reach stderr, terminal.stderr, system.terminal.stderr,
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

    result = ..ok Void()
}

flush_error(
    .stderr: $&Writer = #reach stderr, terminal.stderr, system.terminal.stderr,
) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    result = flush(.self = stderr)
}
