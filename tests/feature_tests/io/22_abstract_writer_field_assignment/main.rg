DummyWriter: Type = (
    .flush_count : Int32 = 0
)

Holder: Type = (
    .writer : $&Writer
)

implement Init#(Holder, (.writer : $&DummyWriter)) (
    .Result: Type = Holder
    .init = (.args: (.writer : $&DummyWriter)) -> (.result: Result) {
        writer ::= ~args.writer

        result.writer = writer
    }
)

main() -> (.status_code: Int32) := {
    writer :: DummyWriter = (
        .flush_count = 0
    )
    holder :: Holder

    holder = Holder(.writer = $&writer)

    writer_address :: UIntNative = $&writer | convert#(.to: UIntNative)(_)
    stored_address :: UIntNative = holder.writer | convert#(.to: UIntNative)(_)
    if writer_address == stored_address {
        status_code = 0
    } else {
        status_code = 1
    }
}

implement Writer#(DummyWriter)(
    .write_byte = (
            .self : $&DummyWriter,
            .byte : UInt8
        ) -> (
            .result : Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))
        ) {
        _ ::= byte
        result = ..ok(.value = Void())
    }

    .flush = (
            .self : $&DummyWriter
        ) -> (
            .result : Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))
        ) {
        self&.flush_count = self&.flush_count + 1
        result = ..ok(.value = Void())
    }
)
