-- Canonical endpoints do not allocate or choose a buffering policy.
-- Programs borrow these files and wrap them in readers or writers as needed.
Terminal: Type = (
    .stdin  : File
    .stdout : File
    .stderr : File
)

once Terminal init(.ffi: $&ForeignFunctionInterface = reach ffi) -> (.result: Terminal) := {
    init_stdin(.p = $&result.stdin)
    init_stdout(.p = $&result.stdout)
    init_stderr(.p = $&result.stderr)
}

Terminal deinit(.self: $&Terminal) -> () := {
    assume error_tracer ::= $&noop_error_tracer
    close(.self = $&self&.stdin)
    close(.self = $&self&.stdout)
    close(.self = $&self&.stderr)
}

read_line_into_buffer(
        .buffer    : $&String,
        .allocator : $&Allocator,
        .reader    : $&Reader,
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..stream_read_failed))
    ) := {
    assume allocator
    assume reader

    clear(.self = buffer)

    while 1 == 1 {
        if has_space(.self = buffer).ok {
        } else {
            break
        }

        next ::= read_byte(.self = reader)
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

                        pushed ::= push_byte(
                            .self      = buffer
                            .byte      = payload
                            .allocator = allocator
                        )
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
        .allocator : $&Allocator,
        .reader    : $&Reader,
    ) -> (
        .result : Errable#(.t: ReadLine, .reasons: (..stream_read_failed, ..out_of_memory))
    ) := {
    assume allocator
    assume reader

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
        ..ok ~payload { line = ~payload }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
            return
        }
    }

    line_complete ::= false

    while 1 == 1 {
        next ::= read_byte(.self = reader)
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
        .value      : StringView,
        .writer     : $&Writer,
        .terminator : StringView  = "\n",
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))
    ) := {
    write(.self = writer, .text = value)!

    result = write(.self = writer, .text = terminator)
}

flush(
        .writer : $&Writer,
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))
    ) := {
    assume writer

    result = flush(.self = writer)
}

print_error(
        .value  : StringView,
        .writer : $&Writer,
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))
    ) := {
    assume writer

    i :: UIntNative = 0

    while i < value.length {
        wrote ::= write_byte(.self = writer, .byte = bytes_get(.view = &value, .index = i).byte)
        match wrote {
            ..ok _ {
            }
            ..error&err {
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
        .writer : $&Writer,
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))
    ) := {
    assume writer

    result = flush(.self = writer)
}

print(
        .value      : &String,
        .writer     : $&Writer,
        .terminator : StringView = "\n",
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))
    ) := {
    assume writer

    result = print(as_view(value), .terminator = terminator)
}

print#(
        .t : Type: Int
    )(
        .value      : t,
        .writer     : $&Writer   = reach writer,
        .terminator : StringView = "\n",
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))
    ) := {
    format_into(.out = writer, .value = value)!

    result = write(.self = writer, .text = terminator)
}

print#(
        .t : Type: Float
    )(
        .value      : t,
        .writer     : $&Writer   = reach writer,
        .terminator : StringView = "\n",
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))
    ) := {
    format_into(.out = writer, .value = value)!

    result = write(.self = writer, .text = terminator)
}
