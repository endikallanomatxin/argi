TerminalStorage : Type = (
    .stdin_file: File
    .stdout_file: File
    .stderr_file: File
)

-- Canonical endpoints do not allocate. Programs may wrap these borrowed
-- streams in BufferedReader/BufferedWriter using their chosen allocator.
Terminal : Type = (
    ._storage: TerminalStorage
    .stdin_file: $&File
    .stdout_file: $&File
    .stderr_file: $&File
    .stdin_reader: $&File
    .stdout_writer: $&File
    .stderr_writer: $&File
    .stdin: $&Reader
    .stdout: $&Writer
    .stderr: $&Writer
)

once init(.p: $&Terminal) -> () := {
    init_stdin(.p = $&p&._storage.stdin_file)
    init_stdout(.p = $&p&._storage.stdout_file)
    init_stderr(.p = $&p&._storage.stderr_file)
    p&.stdin_file = $&p&._storage.stdin_file
    p&.stdout_file = $&p&._storage.stdout_file
    p&.stderr_file = $&p&._storage.stderr_file
    p&.stdin_reader = p&.stdin_file
    p&.stdout_writer = p&.stdout_file
    p&.stderr_writer = p&.stderr_file
    p&.stdin = p&.stdin_file
    p&.stdout = p&.stdout_file
    p&.stderr = p&.stderr_file
}

deinit(.self: $&Terminal) -> () := {
    close(.self = self&.stdin_file)
    close(.self = self&.stdout_file)
    close(.self = self&.stderr_file)
}

read_line_into_buffer(
    .buffer: $&String,
    .allocator: $&Allocator,
    .stdin: $&Reader,
) -> (.result: Errable#(.t: Void, .reasons: (..stream_read_failed))) := {
    assume allocator
    assume stdin

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
    .allocator: $&Allocator,
    .stdin: $&Reader,
) -> (.result: Errable#(.t: ReadLine, .reasons: (..stream_read_failed, ..out_of_memory))) := {
    assume allocator
    assume stdin

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
    .stdout: $&Writer,
) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    assume stdout

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
    .stdout: $&Writer,
) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    assume stdout

    result = flush(.self = stdout)
}

print_error(
    .value: StringView,
    .stderr: $&Writer,
) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    assume stderr

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
    .stderr: $&Writer,
) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    assume stderr

    result = flush(.self = stderr)
}
