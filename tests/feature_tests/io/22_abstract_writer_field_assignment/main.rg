DummyWriter := (
    .flush_count : Int32 = 0
)

Holder := #(.WriterType: Type: Writer#(WriterType)) (
    .writer : $&WriterType
)

HolderInitArgs: Type = #(.WriterType: Type: Writer#(WriterType)) (.writer: $&WriterType)

implement#(.WriterType: Type: Writer#(WriterType)) Init#(
    Holder#(WriterType), HolderInitArgs#(WriterType)
) (
    .Result : Type = Holder#(WriterType)

    .init = HolderInitArgs#(WriterType) -> (.result: Result) {
        _init_writer ::= ~writer

        result.writer = _init_writer
    }
)

main := () -> (.status_code: Int32) {
    writer :: DummyWriter = (
        .flush_count = 0
    )
    holder :: Holder#(DummyWriter)

    holder = Holder#(DummyWriter)(.writer = $&writer)

    writer_address :: UIntNative = $&writer | convert#(.to: UIntNative)(_)
    stored_address :: UIntNative = holder.writer | convert#(.to: UIntNative)(_)
    if writer_address == stored_address {
        status_code = 0
    } else {
        status_code = 1
    }
}

implement Writer#(DummyWriter) (
    .write_byte = (.self: $&DummyWriter, .byte: UInt8) -> (
        .result : Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))
    ) {
        _ ::= byte
        result = ..ok(.value = Void())
    }

    .flush = (.self: $&DummyWriter) -> (
        .result : Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))
    ) {
        self&.flush_count = self&.flush_count + 1
        result = ..ok(.value = Void())
    }
)
