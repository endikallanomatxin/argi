Source := (.byte: UInt8)

Sink := (.byte: UInt8 = 0)

implement Reader#(Source) (
    .read_byte = (.self: $&Source, .error_tracer: $&Virtual#(ErrorTracer)) -> (
        .result : Errable#(ReadByte, (..stream_read_failed))
    ) {
        assume error_tracer

        result = ..ok ..ok self&.byte
    }
)

implement Writer#(Sink) (
    .write_byte = (.self: $&Sink, .byte: UInt8, .error_tracer: $&Virtual#(ErrorTracer)) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) {
        assume error_tracer

        self&.byte = byte
        result = ..ok Void()
    }
    .flush = (.self: $&Sink, .error_tracer: $&Virtual#(ErrorTracer)) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) {
        assume error_tracer

        result = ..ok Void()
    }
)

read_default := #(.Stream: Type: Reader#(Stream)) (
    .source: $&Stream, .error_tracer: $&Virtual#(ErrorTracer)
) -> (.result: UInt8) {
    assume error_tracer
    reader ::= BufferedReader(.base = source)
    match unwrap_or_abort(.value = Reader#().read_byte($&reader)) {
        ..end { abort }
        ..ok byte { result = byte }
    }
}

main := () -> () {
    assume error_tracer ::= $&noop_error_tracer
    first_source :: Source = (.byte = 65)
    second_source :: Source = (.byte = 66)
    first ::= BufferedReader(.base = $&first_source)
    second ::= BufferedReader(.base = $&second_source)
    if length(&first.buffer) == 0 { abort }
    unwrap_or_abort(.value = Reader#().read_byte($&first))
    unwrap_or_abort(.value = Reader#().read_byte($&second))
    match unwrap_or_abort(.value = Reader#().read_byte($&first)) {
        ..end { abort }
        ..ok byte { if byte != 65 { abort } }
    }
    first_sink :: Sink = (.byte = 0)
    second_sink :: Sink = (.byte = 0)
    first_writer ::= BufferedWriter(.base = $&first_sink)
    second_writer ::= BufferedWriter(.base = $&second_sink)
    unwrap_or_abort(.value = Writer#().write_byte($&first_writer, .byte = 65))
    unwrap_or_abort(.value = Writer#().write_byte($&second_writer, .byte = 66))
    unwrap_or_abort(.value = Writer#().flush($&first_writer))
    unwrap_or_abort(.value = Writer#().flush($&second_writer))
    if first_sink.byte != 65 or second_sink.byte != 66 { abort }
    if read_default($&first_source) != 65 { abort }
    readers :: [2]BufferedReader#(Source) = (
        BufferedReader(.base = $&first_source),
        BufferedReader(.base = $&second_source)
    )
    if length(&readers[0].buffer) != 4096 { abort }
    if length(&readers[1].buffer) != 4096 { abort }
}
