DummyOutput := (
    .flush_count : Int32 = 0
)

flush_stdout := #(.WriterType: Type: Writer#(WriterType)) (
    .writer: $&WriterType, .error_tracer: $&Virtual#(ErrorTracer)
) -> (.value: Int32) {
    assume error_tracer
    assume writer

    Writer#().flush(.self = writer)
    value = 0
}

main := () -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    stdout_storage :: DummyOutput = (
        .flush_count = 0
    )
    assume writer ::= $&stdout_storage

    flush_stdout(.writer = $&stdout_storage)
    status_code = stdout_storage.flush_count
}

implement Writer#(DummyOutput) (
    .flush = (.self: $&DummyOutput, .error_tracer: $&Virtual#(ErrorTracer)) -> (
        .result : Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))
    ) {
        assume error_tracer

        self&.flush_count = self&.flush_count + 1
        result = ..ok(.value = Void())
    }

    .write_byte = (.self: $&DummyOutput, .byte: UInt8, .error_tracer: $&Virtual#(ErrorTracer)) -> (
        .result : Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))
    ) {
        assume error_tracer

        _ ::= byte
        result = ..ok(.value = Void())
    }
)
