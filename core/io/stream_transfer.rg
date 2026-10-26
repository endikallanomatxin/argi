-- Transfer specialization belongs to one operation identity for both endpoints.
StreamTransfer<.ReaderType: Type, .WriterType: Type>: Contract = (
    .transfer_stream : (.reader: $&ReaderType, .writer: $&WriterType) -> (
        .result : Errable<
            UIntNative,
            (
                ..stream_read_failed,
                ..stream_write_failed,
                ..stream_flush_failed,
                ..size_overflow
            )
        >
    )
)

-- Transfer implementations consider both endpoints. Buffered writers fill their own
-- free space; plain writers need only one initialized byte. Success counts newly
-- accepted bytes and leaves final flushing and endpoint cleanup to the caller.
implement<.ReaderType: Type: BlockReader<ReaderType>, .WriterType: Type: Writer<WriterType>> StreamTransfer<
    ReaderType, WriterType
> (
    .transfer_stream = (.reader: $&ReaderType, .writer: $&WriterType) -> (
        .result : Errable<
            UIntNative,
            (
                ..stream_read_failed,
                ..stream_write_failed,
                ..stream_flush_failed,
                ..size_overflow
            )
        >
    ) {
        storage ::= zeroed<[1]UInt8>()
        buffer ::= view($&storage)
        copied :: UIntNative = 0

        while true {
            got ::= BlockReader<>.read_block(reader, .buffer = buffer)!
            if got == 0 {
                result = ..ok copied
                return
            }
            if got > 1 { abort }
            if copied + 1 < copied {
                result = ..error(.reason = ..size_overflow)
                return
            }

            Writer<>.write_byte(writer, .byte = storage[0])!
            copied = copied + 1
        }
    }
)

implement<.ReaderType: Type: BlockReader<ReaderType>, .base_type: Type: Writer<base_type>> StreamTransfer<
    ReaderType, BufferedWriter<.base_type: base_type>
> (
    .transfer_stream = (.reader: $&ReaderType, .writer: $&BufferedWriter<.base_type: base_type>) -> (
        .result : Errable<
            UIntNative,
            (
                ..stream_read_failed,
                ..stream_write_failed,
                ..stream_flush_failed,
                ..size_overflow
            )
        >
    ) {
        capacity ::= length(&writer&.buffer).count
        copied :: UIntNative = 0

        if capacity == 0 {
            result = transfer_stream(.writer = writer&.base, .reader = reader)
            return
        }

        while true {
            if writer&.length == capacity {
                buffered_writer_flush(writer)!
            }

            available ::= capacity - writer&.length
            free_space ::= unwrap_or_abort(
                .value = slice(&writer&.buffer, .start = writer&.length, .count = available)
            )
            -- A failed read may modify free space; commit only a successful count.
            got ::= BlockReader<>.read_block(reader, .buffer = free_space)!
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
)
