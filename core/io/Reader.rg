Reader<.Stream: Type>: Contract = (
    .read_byte : (.self: $&Stream) -> (.result: Errable<ReadByte, (..stream_read_failed)>) where {
        on result ..ok {}
        on result ..error { depends_on(result, error_tracer) }
    }
)
