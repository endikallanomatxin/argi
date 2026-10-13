-- Numeric stream formatting has one scoped operation identity. It never flushes
-- implicitly; a failed byte stops emission and preserves preceding writes.
WriteValue#(.Stream: Type, .Value: Type): Contract = (
    .write_value: (.self: $&Stream, .value: Value) -> (
        .result: Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    )
)

_write_integer_value#(.Stream: Type: Writer#(Stream), .Value: Type: Int) := (.self: $&Stream, .value: Value) -> (
    .result: Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
) {
    encoded ::= _decimal_encode#(.t: Value)(.value = value)
    result = write(self, .text = _decimal_view(&encoded).view)
}

_write_float_value#(.Stream: Type: Writer#(Stream), .Value: Type: Float) := (.self: $&Stream, .value: Value) -> (
    .result: Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
) {
    encoded ::= _float_encode(.value = value)
    result = write(self, .text = _float_text_view(&encoded).view)
}

implement#(.Stream: Type: Writer#(Stream)) WriteValue#(Stream, Int8) (
    .write_value = _write_integer_value
)
implement#(.Stream: Type: Writer#(Stream)) WriteValue#(Stream, Int16) (
    .write_value = _write_integer_value
)
implement#(.Stream: Type: Writer#(Stream)) WriteValue#(Stream, Int32) (
    .write_value = _write_integer_value
)
implement#(.Stream: Type: Writer#(Stream)) WriteValue#(Stream, Int64) (
    .write_value = _write_integer_value
)
implement#(.Stream: Type: Writer#(Stream)) WriteValue#(Stream, UInt8) (
    .write_value = _write_integer_value
)
implement#(.Stream: Type: Writer#(Stream)) WriteValue#(Stream, UInt16) (
    .write_value = _write_integer_value
)
implement#(.Stream: Type: Writer#(Stream)) WriteValue#(Stream, UInt32) (
    .write_value = _write_integer_value
)
implement#(.Stream: Type: Writer#(Stream)) WriteValue#(Stream, UInt64) (
    .write_value = _write_integer_value
)
implement#(.Stream: Type: Writer#(Stream)) WriteValue#(Stream, UIntNative) (
    .write_value = _write_integer_value
)
implement#(.Stream: Type: Writer#(Stream)) WriteValue#(Stream, Float16) (
    .write_value = _write_float_value
)
implement#(.Stream: Type: Writer#(Stream)) WriteValue#(Stream, Float32) (
    .write_value = _write_float_value
)
implement#(.Stream: Type: Writer#(Stream)) WriteValue#(Stream, Float64) (
    .write_value = _write_float_value
)
