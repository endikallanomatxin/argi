-- Block protocols preserve partial operations through static and virtual use.
BlockReader: Abstract = (
    read_block(.self: $&Self, .buffer: ArrayView#(.t: UInt8)) -> (
        .result : Errable#(.t: UIntNative, .reasons: (..stream_read_failed))
    )
)

BlockWriter: Abstract = (
    write_block(.self: $&Self, .buffer: ArrayViewRO#(.t: UInt8)) -> (
        .result : Errable#(.t: UIntNative, .reasons: (..stream_write_failed, ..stream_flush_failed))
    )
)

_reader_block#(
        .t : Type: Reader
    )(
        .self   : $&t,
        .buffer : ArrayView#(.t: UInt8)
    ) -> (
        .result : Errable#(.t: UIntNative, .reasons: (..stream_read_failed))
    ) := {
    result = read(.self = self, .buffer = buffer)
}

_writer_block#(
        .t : Type: Writer
    )(
        .self   : $&t,
        .buffer : ArrayViewRO#(.t: UInt8)
    ) -> (
        .result : Errable#(.t: UIntNative, .reasons: (..stream_write_failed, ..stream_flush_failed))
    ) := {
    index :: UIntNative = 0
    while index < length(.self = &buffer).count {
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
        .result : Errable#(.t: Void, .reasons: (..stream_read_failed, ..unexpected_eof))
    ) := {
    total ::= length(.self = &buffer).count
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
        .result : Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))
    ) := {
    total ::= length(.self = &buffer).count
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
            .t       : UIntNative,
            .reasons : (
                ..stream_read_failed,
                ..stream_write_failed,
                ..stream_flush_failed,
                ..invalid_stream_buffer,
                ..size_overflow
            )
        )
    ) := {
    size ::= length(.self = &buffer).count
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
        .result : Errable#(.t: ReadUntil, .reasons: (..stream_read_failed))
    ) := {
    count :: UIntNative = 0
    while count < length(.self = &buffer).count {
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
        .result : Errable#(.t: UIntNative, .reasons: (..stream_read_failed))
    ) := {
    result = read(.self = self, .buffer = buffer)
}

read_block(
        .self   : $&ProcessStream,
        .buffer : ArrayView#(.t: UInt8)
    ) -> (
        .result : Errable#(.t: UIntNative, .reasons: (..stream_read_failed))
    ) := {
    result = read(.self = self, .buffer = buffer)
}

write_block(
        .self   : $&ProcessStream,
        .buffer : ArrayViewRO#(.t: UInt8)
    ) -> (
        .result : Errable#(.t: UIntNative, .reasons: (..stream_write_failed, ..stream_flush_failed))
    ) := { result = _writer_block(.self = self, .buffer = buffer) }

read_block#(
        .base_type : Type: Reader
    )(
        .self   : $&BufferedReader#(.base_type: base_type),
        .buffer : ArrayView#(.t: UInt8)
    ) -> (
        .result : Errable#(.t: UIntNative, .reasons: (..stream_read_failed))
    ) := { result = _reader_block(.self = self, .buffer = buffer) }

write_block#(
        .base_type : Type: Writer
    )(
        .self   : $&BufferedWriter#(.base_type: base_type),
        .buffer : ArrayViewRO#(.t: UInt8)
    ) -> (
        .result : Errable#(.t: UIntNative, .reasons: (..stream_write_failed, ..stream_flush_failed))
    ) := { result = _writer_block(.self = self, .buffer = buffer) }

read_exact(
        .self   : $&Virtual#(.abstract: BlockReader),
        .buffer : ArrayView#(.t: UInt8)
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..stream_read_failed, ..unexpected_eof))
    ) := {
    total ::= length(.self = &buffer).count
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
        .result : Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))
    ) := {
    total ::= length(.self = &buffer).count
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
            .t       : UIntNative,
            .reasons : (
                ..stream_read_failed,
                ..stream_write_failed,
                ..stream_flush_failed,
                ..invalid_stream_buffer,
                ..size_overflow
            )
        )
    ) := {
    size ::= length(.self = &buffer).count
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
            .t       : UIntNative,
            .reasons : (
                ..stream_read_failed,
                ..stream_write_failed,
                ..stream_flush_failed,
                ..invalid_stream_buffer,
                ..size_overflow
            )
        )
    ) := {
    size ::= length(.self = &buffer).count
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
            .t       : UIntNative,
            .reasons : (
                ..stream_read_failed,
                ..stream_write_failed,
                ..stream_flush_failed,
                ..invalid_stream_buffer,
                ..size_overflow
            )
        )
    ) := {
    size ::= length(.self = &buffer).count
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
