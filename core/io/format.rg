-- Formatting writes through the ordinary Writer contract and never flushes
-- implicitly. A failed byte stops emission; preceding bytes remain written.
format_into#(
        .t : Type: Int
    )(
        .out   : $&Writer,
        .value : t,
    ) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) := {
    encoded ::= _decimal_encode#(.t: t)(.value = value)

    result = write(.self = out, .text = _decimal_view(.self = &encoded).view)
}

write#(
        .t : Type: Int
    )(
        .self  : $&Writer,
        .value : t,
    ) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) := {
    result = format_into(.out = self, .value = value)
}

format_into#(
        .t : Type: Float
    )(
        .out   : $&Writer,
        .value : t
    ) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) := {
    encoded ::= _float_encode(.value = value)

    result = write(.self = out, .text = _float_text_view(.self = &encoded).view)
}

write#(
        .t : Type: Float
    )(
        .self  : $&Writer,
        .value : t
    ) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) := {
    result = format_into(.out = self, .value = value)
}
