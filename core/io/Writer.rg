Writer<.Stream: Type>: Contract = (
    .write_byte : (.self: $&Stream, .byte: UInt8) -> (
        .result: Errable<Void, (..stream_write_failed, ..stream_flush_failed)>
    ) where {
        on result ..ok {}
        on result ..error { depends_on(result, error_tracer) }
    }
    .flush : (.self: $&Stream) -> (
        .result: Errable<Void, (..stream_write_failed, ..stream_flush_failed)>
    ) where {
        on result ..ok {}
        on result ..error { depends_on(result, error_tracer) }
    }
)
