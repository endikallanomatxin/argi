-- Block protocols preserve partial operations through static and virtual use.

..unexpected_eof
..invalid_stream_buffer

read_exact#(.SelfType: Type: BlockReader#(SelfType))(
    .self: $&SelfType, .buffer: ArrayView#(.t: UInt8)
) -> (.result: Errable#(Void, (..stream_read_failed, ..unexpected_eof))) := {
    total ::= length(&buffer).count
    count :: UIntNative = 0

    while count < total {
        tail ::= unwrap_or_abort(
            .value = slice(&buffer, .start = count, .count = [total - count])
        )
        got ::= BlockReader#().read_block(self, .buffer = tail)!
        if got == 0 {
            result = ..error(.reason = ..unexpected_eof)
            return
        }
        if got > total - count { abort }
        count = count + got
    }

    result = ..ok Void()
}

write_all#(.SelfType: Type: BlockWriter#(SelfType))(
    .self: $&SelfType, .buffer: ArrayViewRO#(.t: UInt8)
) -> (.result: Errable#(Void, (..stream_write_failed, ..stream_flush_failed))) := {
    total ::= length(&buffer).count
    count :: UIntNative = 0

    while count < total {
        tail ::= unwrap_or_abort(
            .value = slice(&buffer, .start = count, .count = [total - count])
        )
        wrote ::= BlockWriter#().write_block(self, .buffer = tail)!
        if wrote == 0 {
            result = ..error(.reason = ..stream_write_failed)
            return
        }
        if wrote > total - count { abort }
        count = count + wrote
    }

    result = ..ok Void()
}

copy_stream#(
    .ReaderType: Type: BlockReader#(ReaderType), .WriterType: Type: BlockWriter#(WriterType)
)(.reader: $&ReaderType, .writer: $&WriterType, .buffer: ArrayView#(.t: UInt8)) -> (
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
        got ::= BlockReader#().read_block(reader, .buffer = buffer)!
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
        prefix ::= unwrap_or_abort(.value = slice(&buffer, .start = 0, .count = got))
        readonly ::= as_readonly(&prefix).view
        write_all(writer, .buffer = readonly)!
        copied = grown
    }
}

ReadUntilEnd: Type = (..delimiter, ..end, ..limit)

implement ImplicitlyCopyable#(ReadUntilEnd) ()

ReadUntil: Type = (.count: UIntNative, .termination: ReadUntilEnd)

implement ImplicitlyCopyable#(ReadUntil) ()

read_until#(.SelfType: Type: Reader#(SelfType))(
    .self: $&SelfType, .buffer: ArrayView#(.t: UInt8), .delimiter: UInt8
) -> (.result: Errable#(ReadUntil, (..stream_read_failed))) := {
    count :: UIntNative = 0

    while count < length(&buffer).count {
        byte ::= Reader#().read_byte(self)!
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
                pointer ::= unwrap_or_abort(
                    .value = get_mutable_reference($&buffer, .index = count)
                )
                pointer&= value
                count = count + 1
            }
        }
    }

    result = ..ok(.count = count, .termination = ..limit)
}
