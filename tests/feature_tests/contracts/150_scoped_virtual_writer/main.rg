Output#(.Stream: Type): Contract = (
    .write_byte : (.self: $&Stream, .byte: UInt8, .error_tracer: $&Virtual#(ErrorTracer)) -> (
        .result : Errable#(Void, (..stream_write_failed))
    ) where {
        on result ..ok {}
        on result ..error { depends_on(result, error_tracer) }
    }
    .flush : (.self: $&Stream) -> () where {}
)

Sink := (.last: UInt8 = 0, .flushed: Bool = false)

implement Output#(Sink) (
    .write_byte = (.self: $&Sink, .byte: UInt8, .error_tracer: $&Virtual#(ErrorTracer)) -> (
        .result : Errable#(Void, (..stream_write_failed))
    ) {
        assume error_tracer

        self&.last = byte
        result = ..ok Void()
    }
    .flush = (.self: $&Sink) -> () {
        self&.flushed = true
    }
)

-- An ordinary identity with the same spelling must not populate the virtual slot.
flush := (.self: $&Sink) -> () { abort }

main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    sink ::= Sink()
    erased ::= to_virtual#(.contract: Output)(.value = $&sink)
    match Output#().write_byte($&erased, .byte = 42) { ..ok _ {} ..error _ { abort } }
    Output#().flush($&erased)
    if sink.last != 42 or sink.flushed == false { abort }
}
