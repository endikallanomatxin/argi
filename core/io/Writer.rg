Writer#(.Stream: Type): Contract = (
    .write_byte : (.self: $&Stream, .byte: UInt8) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) where {
        on result ..ok {}
        on result ..error {}

    }
    .flush : (.self: $&Stream) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) where {
        on result ..ok {}
        on result ..error {}

    }
)
