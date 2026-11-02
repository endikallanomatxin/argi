Output#(.Stream: Type): Contract = (
    .write_byte : (.self: $&Stream, .byte: UInt8) -> (
        .result : Errable#(Void, (..stream_write_failed))
    ) where {
        on result ..ok {}

    }
    .flush : (.self: $&Stream) -> () where {}
)

Sink := (.last: UInt8 = 0, .flushed: Bool = false)

implement Output#(Sink) (
    .write_byte = (.self: $&Sink, .byte: UInt8) -> (
        .result : Errable#(Void, (..stream_write_failed))
    ) {

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

    sink ::= Sink()
    erased ::= to_virtual#(.contract: Output)(.value = $&sink)
    match Output#().write_byte($&erased, .byte = 42) { ..ok _ {} ..error _ { abort } }
    Output#().flush($&erased)
    if sink.last != 42 or sink.flushed == false { abort }
}
