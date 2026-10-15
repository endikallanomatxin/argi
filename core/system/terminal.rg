-- Canonical endpoints do not allocate or choose a buffering policy.
-- Programs borrow these files and wrap them in readers or writers as needed.
Terminal: Type = (
    .stdin  : File
    .stdout : File
    .stderr : File
)

once _acquire_terminal := (.args: (.ffi: $&ForeignFunctionInterface = reach ffi)) -> (
    .result : Terminal
) {
    assume ffi := args.ffi

    init_stdin(.p = $&result.stdin)
    init_stdout(.p = $&result.stdout)
    init_stderr(.p = $&result.stderr)
}

implement Init#(Terminal, (.ffi: $&ForeignFunctionInterface = reach ffi)) (
    .Result : Type = Terminal
    .init   = _acquire_terminal
)

implement Deinit#(Terminal) (
    .deinit = (.self: $&Terminal) -> () {
        assume error_tracer ::= $&noop_error_tracer
        close($&self&.stdin)
        close($&self&.stdout)
        close($&self&.stderr)
    }
)

read_line_into_buffer#(
    .AllocatorType: Type: Allocator#(AllocatorType), .ReaderType: Type: Reader#(ReaderType)
)(.buffer: $&String, .allocator: $&AllocatorType, .reader: $&ReaderType) -> (
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

        next ::= Reader#().read_byte(reader)
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

                        pushed ::= push_byte(buffer, .byte = payload, .allocator = allocator)
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

read_line#(
    .AllocatorType: Type: Allocator#(AllocatorType), .ReaderType: Type: Reader#(ReaderType)
)(.allocator: $&AllocatorType, .reader: $&ReaderType) -> (
    .result : Errable#(ReadLine, (..stream_read_failed, ..out_of_memory))
) := {
    assume allocator
    assume reader

    -- The result owns independent text. Lexical cleanup releases partial
    -- lines on failure; a successfully moved line belongs to the caller.
    line ::= string_with_capacity(.capacity = 16)!

    while true {
        match Reader#().read_byte(reader)! {
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

flush#(.WriterType: Type: Writer#(WriterType)) := (.writer: $&WriterType) -> (
    .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
) {
    assume writer

    result = Writer#().flush(.self = writer)
}

print_error#(.WriterType: Type: Writer#(WriterType))(.value: StringView, .writer: $&WriterType) -> (
    .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
) := {
    assume writer

    i :: UIntNative = 0

    while i < value.length {
        wrote ::= Writer#(
        ).write_byte(writer, .byte = bytes_get(.view = &value, .index = i).byte)
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

flush_error#(.WriterType: Type: Writer#(WriterType))(.writer: $&WriterType) -> (
    .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
) := {
    assume writer

    result = Writer#().flush(.self = writer)
}

-- Rendering is selected by WriteValue, not an ordinary print overload family.
print#(.Value: Type, .Stream: Type: WriteValue#(Stream, Value)) := (
    .value: Value, .writer: $&Stream = reach writer, .terminator: StringView = "\n"
) -> (.result: Errable#(Void, (..stream_write_failed, ..stream_flush_failed))) {
    write(.self = writer, .value = ~value)!
    result = write(.self = writer, .value = terminator)
}
