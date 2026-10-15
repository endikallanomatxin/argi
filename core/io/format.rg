-- Numeric stream formatting has one scoped operation identity. It never flushes
-- implicitly; a failed byte stops emission and preserves preceding writes.
_write_integer_value#(
        .Stream : Type: Writer#(Stream),
        .Value  : Type: Int
    ) := (
        .self  : $&Stream,
        .value : Value
    ) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) {
    encoded ::= _decimal_encode#(.t: Value)(.value = value)
    result = write(self, .value = _decimal_view(&encoded).view)
}

_write_float_value#(
        .Stream : Type: Writer#(Stream),
        .Value  : Type: Float
    ) := (
        .self  : $&Stream,
        .value : Value
    ) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) {
    encoded ::= _float_encode(.value = value)
    result = write(self, .value = _float_text_view(&encoded).view)
}

implement#(.Stream: Type: Writer#(Stream)) WriteValue#(Stream, Int8) (
    .Result      : Type                 = Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    .write_value = _write_integer_value
)

implement#(.Stream: Type: Writer#(Stream)) WriteValue#(Stream, Int16) (
    .Result      : Type                 = Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    .write_value = _write_integer_value
)

implement#(.Stream: Type: Writer#(Stream)) WriteValue#(Stream, Int32) (
    .Result      : Type                 = Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    .write_value = _write_integer_value
)

implement#(.Stream: Type: Writer#(Stream)) WriteValue#(Stream, Int64) (
    .Result      : Type                 = Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    .write_value = _write_integer_value
)

implement#(.Stream: Type: Writer#(Stream)) WriteValue#(Stream, UInt8) (
    .Result      : Type                 = Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    .write_value = _write_integer_value
)

implement#(.Stream: Type: Writer#(Stream)) WriteValue#(Stream, UInt16) (
    .Result      : Type                 = Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    .write_value = _write_integer_value
)

implement#(.Stream: Type: Writer#(Stream)) WriteValue#(Stream, UInt32) (
    .Result      : Type                 = Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    .write_value = _write_integer_value
)

implement#(.Stream: Type: Writer#(Stream)) WriteValue#(Stream, UInt64) (
    .Result      : Type                 = Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    .write_value = _write_integer_value
)

implement#(.Stream: Type: Writer#(Stream)) WriteValue#(Stream, UIntNative) (
    .Result      : Type                 = Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    .write_value = _write_integer_value
)

implement#(.Stream: Type: Writer#(Stream)) WriteValue#(Stream, Float16) (
    .Result      : Type               = Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    .write_value = _write_float_value
)

implement#(.Stream: Type: Writer#(Stream)) WriteValue#(Stream, Float32) (
    .Result      : Type               = Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    .write_value = _write_float_value
)

implement#(.Stream: Type: Writer#(Stream)) WriteValue#(Stream, Float64) (
    .Result      : Type               = Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    .write_value = _write_float_value
)
