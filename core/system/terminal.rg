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
    close($&self&.stdin)
    close($&self&.stdout)
    close($&self&.stderr)
}

read_line_into_buffer(
        .buffer    : $&String,
        .allocator : $&Allocator,
        .reader    : $&Reader,
    ) -> (
        .result : Errable#(Void, (..stream_read_failed))
    ) := {
    assume allocator
    assume reader

    clear(buffer)

    while 1 == 1 {
        if has_space(buffer).ok {
        } else {
            break
        }

        next ::= read_byte(reader)
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
                            buffer
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
        .result : Errable#(ReadLine, (..stream_read_failed, ..out_of_memory))
    ) := {
    assume allocator
    assume reader

    -- The result owns independent text. Lexical cleanup releases partial
    -- lines on failure; a successfully moved line belongs to the caller.
    line ::= String(.capacity = 16)!

    while true {
        match read_byte(reader)! {
            ..end {
                if line.length == 0 {
                    result = ..ok ..end
                    return
                }
                break
            }
            ..ok byte {
                if byte == 10 { break }
                push_byte($&line, .byte = byte)!
            }
        }
    }

    result = ..ok ..ok ~line
}

print(
        .value      : StringView,
        .writer     : $&Writer,
        .terminator : StringView  = "\n",
    ) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) := {
    write(writer, .text = value)!

    result = write(writer, .text = terminator)
}

flush(
        .writer : $&Writer,
    ) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) := {
    assume writer

    result = flush(.self = writer)
}

print_error(
        .value  : StringView,
        .writer : $&Writer,
    ) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) := {
    assume writer

    i :: UIntNative = 0

    while i < value.length {
        wrote ::= write_byte(writer, .byte = bytes_get(.view = &value, .index = i).byte)
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
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) := {
    assume writer

    result = flush(.self = writer)
}

print(
        .value      : &String,
        .writer     : $&Writer,
        .terminator : StringView = "\n",
    ) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
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
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) := {
    format_into(.out = writer, .value = value)!

    result = write(writer, .text = terminator)
}

print#(
        .t : Type: Float
    )(
        .value      : t,
        .writer     : $&Writer   = reach writer,
        .terminator : StringView = "\n",
    ) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) := {
    format_into(.out = writer, .value = value)!

    result = write(writer, .text = terminator)
}
