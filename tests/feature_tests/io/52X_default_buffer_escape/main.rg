Source: Type = ()

implement Reader#(Source) (
    .read_byte = (.self: $&Source, .error_tracer: $&Virtual#(ErrorTracer)) -> (
        .result : Errable#(ReadByte, (..stream_read_failed))
    ) {
        assume error_tracer

        result = ..ok ..end
    }
)

make_reader := (.source: $&Source, .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : BufferedReader#(Source)
) {
    assume error_tracer
    result = BufferedReader(.base = source)
}

main := () -> () {
    assume error_tracer ::= $&noop_error_tracer
    source :: Source = ()
    reader ::= make_reader($&source)
    _ ::= Reader#().read_byte($&reader)
}
