-- Block protocols preserve partial operations through static and virtual use.
BlockReader: Abstract = (
    read_block(.self: $&Self, .buffer: ArrayView#(.t: UInt8)) -> (
        .result : Errable#(UIntNative, (..stream_read_failed))
    )
)

BlockWriter: Abstract = (
    write_block(.self: $&Self, .buffer: ArrayViewRO#(.t: UInt8)) -> (
        .result : Errable#(UIntNative, (..stream_write_failed, ..stream_flush_failed))
    )
)

_reader_block#(
        .t : Type: Reader
    )(
        .self   : $&t,
        .buffer : ArrayView#(.t: UInt8)
    ) -> (
        .result : Errable#(UIntNative, (..stream_read_failed))
    ) := {
    result = read(.self = self, .buffer = buffer)
}

_writer_block#(
        .t : Type: Writer
    )(
        .self   : $&t,
        .buffer : ArrayViewRO#(.t: UInt8)
    ) -> (
        .result : Errable#(UIntNative, (..stream_write_failed, ..stream_flush_failed))
    ) := {
    index :: UIntNative = 0

    while index < length(&buffer).count {
        byte ::= unwrap_or_abort(.value = get_ro_ref(.self = &buffer, .index = index))
        write_byte(.self = self, .byte = byte&)!
        index = index + 1
    }

    result = ..ok index
}

File implements BlockReader
File implements BlockWriter
ProcessStream implements BlockReader
ProcessStream implements BlockWriter
BufferedReader#(.base_type: Type: Reader) implements BlockReader
BufferedWriter#(.base_type: Type: Writer) implements BlockWriter
TcpConnection implements BlockReader
TcpConnection implements BlockWriter

..unexpected_eof
..invalid_stream_buffer

read_exact(
        .self   : $&BlockReader,
        .buffer : ArrayView#(.t: UInt8)
    ) -> (
        .result : Errable#(Void, (..stream_read_failed, ..unexpected_eof))
    ) := {
    total ::= length(&buffer).count
    count :: UIntNative = 0

    while count < total {
        tail ::= unwrap_or_abort(
            .value = slice(
                .self  = &buffer
                .start = count
                .count = [
                    total
                    - count
                ]
            )
        )
        got ::= read_block(.self = self, .buffer = tail)!
        if got == 0 {
            result = ..error(.reason = ..unexpected_eof)
            return
        }
        if got > total - count { abort }
        count = count + got
    }

    result = ..ok Void()
}

write_all(
        .self   : $&BlockWriter,
        .buffer : ArrayViewRO#(.t: UInt8)
    ) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) := {
    total ::= length(&buffer).count
    count :: UIntNative = 0

    while count < total {
        tail ::= unwrap_or_abort(
            .value = slice(
                .self  = &buffer
                .start = count
                .count = [
                    total
                    - count
                ]
            )
        )
        wrote ::= write_block(.self = self, .buffer = tail)!
        if wrote == 0 {
            result = ..error(.reason = ..stream_write_failed)
            return
        }
        if wrote > total - count { abort }
        count = count + wrote
    }

    result = ..ok Void()
}

copy_stream(
        .reader : $&BlockReader,
        .writer : $&BlockWriter,
        .buffer : ArrayView#(.t: UInt8)
    ) -> (
        .result : Errable#(
            UIntNative,
            (
                ..stream_read_failed,
                ..stream_write_failed,
                ..stream_flush_failed,
                ..invalid_stream_buffer,
                ..size_overflow
            )
        )
    ) := {
    size ::= length(&buffer).count

    if size == 0 {
        result = ..error(.reason = ..invalid_stream_buffer)
        return
    }

    copied :: UIntNative = 0

    while true {
        got ::= read_block(.self = reader, .buffer = buffer)!
        if got == 0 {
            result = ..ok copied
            return
        }
        if got > size { abort }
        grown ::= copied + got
        if grown < copied {
            result = ..error(.reason = ..size_overflow)
            return
        }
        prefix ::= unwrap_or_abort(.value = slice(.self = &buffer, .start = 0, .count = got))
        readonly ::= as_readonly(.self = &prefix).view
        write_all(.self = writer, .buffer = readonly)!
        copied = grown
    }
}

ReadUntilEnd: Type = (..delimiter, ..end, ..limit)

ReadUntilEnd implements ImplicitlyCopyable

ReadUntil: Type = (.count: UIntNative, .termination: ReadUntilEnd)

ReadUntil implements ImplicitlyCopyable

read_until(
        .self      : $&Reader,
        .buffer    : ArrayView#(.t: UInt8),
        .delimiter : UInt8
    ) -> (
        .result : Errable#(ReadUntil, (..stream_read_failed))
    ) := {
    count :: UIntNative = 0

    while count < length(&buffer).count {
        byte ::= read_byte(.self = self)!
        match byte {
            ..end {
                result = ..ok(.count = count, .termination = ..end)
                return
            }
            ..ok value {
                if value == delimiter {
                    result = ..ok(.count = count, .termination = ..delimiter)
                    return
                }
                pointer ::= unwrap_or_abort(.value = get_rw_ref(.self = $&buffer, .index = count))
                pointer&= value
                count = count + 1
            }
        }
    }

    result = ..ok(.count = count, .termination = ..limit)
}

read_block(
        .self   : $&File,
        .buffer : ArrayView#(.t: UInt8)
    ) -> (
        .result : Errable#(UIntNative, (..stream_read_failed))
    ) := {
    result = read(.self = self, .buffer = buffer)
}

read_block(
        .self   : $&ProcessStream,
        .buffer : ArrayView#(.t: UInt8)
    ) -> (
        .result : Errable#(UIntNative, (..stream_read_failed))
    ) := {
    result = read(.self = self, .buffer = buffer)
}

write_block(
        .self   : $&ProcessStream,
        .buffer : ArrayViewRO#(.t: UInt8)
    ) -> (
        .result : Errable#(UIntNative, (..stream_write_failed, ..stream_flush_failed))
    ) := {
    result = _writer_block(.self = self, .buffer = buffer)
}

read_block#(
        .base_type : Type: Reader
    )(
        .self   : $&BufferedReader#(.base_type: base_type),
        .buffer : ArrayView#(.t: UInt8)
    ) -> (
        .result : Errable#(UIntNative, (..stream_read_failed))
    ) := {
    result = _reader_block(.self = self, .buffer = buffer)
}

write_block#(
        .base_type : Type: Writer
    )(
        .self   : $&BufferedWriter#(.base_type: base_type),
        .buffer : ArrayViewRO#(.t: UInt8)
    ) -> (
        .result : Errable#(UIntNative, (..stream_write_failed, ..stream_flush_failed))
    ) := {
    result = _writer_block(.self = self, .buffer = buffer)
}

read_exact(
        .self   : $&Virtual#(.abstract: BlockReader),
        .buffer : ArrayView#(.t: UInt8)
    ) -> (
        .result : Errable#(Void, (..stream_read_failed, ..unexpected_eof))
    ) := {
    total ::= length(&buffer).count
    count :: UIntNative = 0

    while count < total {
        tail ::= unwrap_or_abort(
            .value = slice(
                .self  = &buffer
                .start = count
                .count = [
                    total
                    - count
                ]
            )
        )
        got ::= read_block(.self = self, .buffer = tail)!
        if got == 0 {
            result = ..error(.reason = ..unexpected_eof)
            return
        }
        if got > total - count { abort }
        count = count + got
    }

    result = ..ok Void()
}

write_all(
        .self   : $&Virtual#(.abstract: BlockWriter),
        .buffer : ArrayViewRO#(.t: UInt8)
    ) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) := {
    total ::= length(&buffer).count
    count :: UIntNative = 0

    while count < total {
        tail ::= unwrap_or_abort(
            .value = slice(
                .self  = &buffer
                .start = count
                .count = [
                    total
                    - count
                ]
            )
        )
        wrote ::= write_block(.self = self, .buffer = tail)!
        if wrote == 0 {
            result = ..error(.reason = ..stream_write_failed)
            return
        }
        if wrote > total - count { abort }
        count = count + wrote
    }

    result = ..ok Void()
}

copy_stream(
        .reader : $&Virtual#(.abstract: BlockReader),
        .writer : $&BlockWriter,
        .buffer : ArrayView#(.t: UInt8)
    ) -> (
        .result : Errable#(
            UIntNative,
            (
                ..stream_read_failed,
                ..stream_write_failed,
                ..stream_flush_failed,
                ..invalid_stream_buffer,
                ..size_overflow
            )
        )
    ) := {
    size ::= length(&buffer).count

    if size == 0 {
        result = ..error(.reason = ..invalid_stream_buffer)
        return
    }

    copied :: UIntNative = 0

    while true {
        got ::= read_block(.self = reader, .buffer = buffer)!
        if got == 0 {
            result = ..ok copied
            return
        }
        if got > size { abort }
        grown ::= copied + got
        if grown < copied {
            result = ..error(.reason = ..size_overflow)
            return
        }
        prefix ::= unwrap_or_abort(.value = slice(.self = &buffer, .start = 0, .count = got))
        readonly ::= as_readonly(.self = &prefix).view
        write_all(.self = writer, .buffer = readonly)!
        copied = grown
    }
}

copy_stream(
        .reader : $&BlockReader,
        .writer : $&Virtual#(.abstract: BlockWriter),
        .buffer : ArrayView#(.t: UInt8)
    ) -> (
        .result : Errable#(
            UIntNative,
            (
                ..stream_read_failed,
                ..stream_write_failed,
                ..stream_flush_failed,
                ..invalid_stream_buffer,
                ..size_overflow
            )
        )
    ) := {
    size ::= length(&buffer).count

    if size == 0 {
        result = ..error(.reason = ..invalid_stream_buffer)
        return
    }

    copied :: UIntNative = 0

    while true {
        got ::= read_block(.self = reader, .buffer = buffer)!
        if got == 0 {
            result = ..ok copied
            return
        }
        if got > size { abort }
        grown ::= copied + got
        if grown < copied {
            result = ..error(.reason = ..size_overflow)
            return
        }
        prefix ::= unwrap_or_abort(.value = slice(.self = &buffer, .start = 0, .count = got))
        readonly ::= as_readonly(.self = &prefix).view
        write_all(.self = writer, .buffer = readonly)!
        copied = grown
    }
}

copy_stream(
        .reader : $&Virtual#(.abstract: BlockReader),
        .writer : $&Virtual#(.abstract: BlockWriter),
        .buffer : ArrayView#(.t: UInt8)
    ) -> (
        .result : Errable#(
            UIntNative,
            (
                ..stream_read_failed,
                ..stream_write_failed,
                ..stream_flush_failed,
                ..invalid_stream_buffer,
                ..size_overflow
            )
        )
    ) := {
    size ::= length(&buffer).count

    if size == 0 {
        result = ..error(.reason = ..invalid_stream_buffer)
        return
    }

    copied :: UIntNative = 0

    while true {
        got ::= read_block(.self = reader, .buffer = buffer)!
        if got == 0 {
            result = ..ok copied
            return
        }
        if got > size { abort }
        grown ::= copied + got
        if grown < copied {
            result = ..error(.reason = ..size_overflow)
            return
        }
        prefix ::= unwrap_or_abort(.value = slice(.self = &buffer, .start = 0, .count = got))
        readonly ::= as_readonly(.self = &prefix).view
        write_all(.self = writer, .buffer = readonly)!
        copied = grown
    }
}

-- Transfer dispatch considers both endpoints. Buffered writers fill their own
-- free space; plain writers need only one initialized byte. Success counts newly
-- accepted bytes and leaves final flushing and endpoint cleanup to the caller.
transfer_stream(
        .reader : $&BlockReader,
        .writer : $&Writer
    ) -> (
        .result : Errable#(
            UIntNative,
            (..stream_read_failed, ..stream_write_failed, ..stream_flush_failed, ..size_overflow)
        )
    ) := {
    storage ::= zeroed#([1]UInt8)()
    buffer ::= view($&storage)
    copied :: UIntNative = 0

    while true {
        got ::= read_block(.self = reader, .buffer = buffer)!
        if got == 0 {
            result = ..ok copied
            return
        }
        if got > 1 { abort }
        if copied + 1 < copied {
            result = ..error(.reason = ..size_overflow)
            return
        }

        write_byte(.self = writer, .byte = storage[0])!
        copied = copied + 1
    }
}

transfer_stream(
        .reader : $&Virtual#(.abstract: BlockReader),
        .writer : $&Writer
    ) -> (
        .result : Errable#(
            UIntNative,
            (..stream_read_failed, ..stream_write_failed, ..stream_flush_failed, ..size_overflow)
        )
    ) := {
    storage ::= zeroed#([1]UInt8)()
    buffer ::= view($&storage)
    copied :: UIntNative = 0

    while true {
        got ::= read_block(.self = reader, .buffer = buffer)!
        if got == 0 {
            result = ..ok copied
            return
        }
        if got > 1 { abort }
        if copied + 1 < copied {
            result = ..error(.reason = ..size_overflow)
            return
        }

        write_byte(.self = writer, .byte = storage[0])!
        copied = copied + 1
    }
}

transfer_stream#(
        .base_type : Type: Writer
    )(
        .reader : $&BlockReader,
        .writer : $&BufferedWriter#(.base_type: base_type)
    ) -> (
        .result : Errable#(
            UIntNative,
            (..stream_read_failed, ..stream_write_failed, ..stream_flush_failed, ..size_overflow)
        )
    ) := {
    capacity ::= length(&writer&.buffer).count
    copied :: UIntNative = 0

    if capacity == 0 {
        result = transfer_stream(.writer = writer&.base, .reader = reader)
        return
    }

    while true {
        if writer&.length == capacity {
            buffered_writer_flush(.self = writer)!
        }

        available ::= capacity - writer&.length
        free_space ::= unwrap_or_abort(
            .value = slice(.self = &writer&.buffer, .start = writer&.length, .count = available)
        )
        -- A failed read may modify free space; commit only a successful count.
        got ::= read_block(.self = reader, .buffer = free_space)!
        if got == 0 {
            result = ..ok copied
            return
        }
        if got > available { abort }
        grown ::= copied + got
        if grown < copied {
            result = ..error(.reason = ..size_overflow)
            return
        }

        writer&.length = writer&.length + got
        copied = grown
    }
}

transfer_stream#(
        .base_type : Type: Writer
    )(
        .reader : $&Virtual#(.abstract: BlockReader),
        .writer : $&BufferedWriter#(.base_type: base_type)
    ) -> (
        .result : Errable#(
            UIntNative,
            (..stream_read_failed, ..stream_write_failed, ..stream_flush_failed, ..size_overflow)
        )
    ) := {
    capacity ::= length(&writer&.buffer).count
    copied :: UIntNative = 0

    if capacity == 0 {
        result = transfer_stream(.writer = writer&.base, .reader = reader)
        return
    }

    while true {
        if writer&.length == capacity {
            buffered_writer_flush(.self = writer)!
        }

        available ::= capacity - writer&.length
        free_space ::= unwrap_or_abort(
            .value = slice(.self = &writer&.buffer, .start = writer&.length, .count = available)
        )
        -- A failed read may modify free space; commit only a successful count.
        got ::= read_block(.self = reader, .buffer = free_space)!
        if got == 0 {
            result = ..ok copied
            return
        }
        if got > available { abort }
        grown ::= copied + got
        if grown < copied {
            result = ..error(.reason = ..size_overflow)
            return
        }

        writer&.length = writer&.length + got
        copied = grown
    }
}
