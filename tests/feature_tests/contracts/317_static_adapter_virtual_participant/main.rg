Input := (.position: UIntNative = 0)

implement Reader#(Input) (
    .read_byte = (.self: $&Input, .error_tracer: $&Virtual#(ErrorTracer)) -> (
        .result : Errable#(ReadByte, (..stream_read_failed))
    ) {
        assume error_tracer

        if self&.position == 0 {
            self&.position = 1
            result = ..ok ..ok 65
        } else {
            result = ..ok ..end
        }
    }
)

read_erased := #(.Stream: Type: Reader#(Stream)) (
    .self         : $&Stream,
    .buffer       : MutableArrayView#(.t: UInt8),
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: BufferReading#(Stream).Result) {
    assume error_tracer
    result = read(.self = self, .buffer = buffer)
}

main := () -> () {
    assume error_tracer ::= $&noop_error_tracer
    input ::= Input()
    erased ::= to_virtual#(.contract: Reader)(.value = $&input)
    bytes: [2]UInt8 = (0, 0)
    match read_erased(.self = $&erased, .buffer = view($&bytes)) {
        ..error _ { abort }
        ..ok count { if count != 1 { abort } }
    }
    if bytes[0] != 65 or bytes[1] != 0 { abort }
    if input.position != 1 { abort }
}
