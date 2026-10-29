DummyInput := (
    .failed : Bool = false
)

implement Reader#(DummyInput) (
    .read_byte = (.self: $&DummyInput, .error_tracer: $&Virtual#(ErrorTracer)) -> (
        .result : Errable#(.t: ReadByte, .reasons: (..stream_read_failed))
    ) {
        assume error_tracer

        result = ..error(.reason = ..stream_read_failed)
    }
)

main := (.system: System) -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    stdin_storage :: DummyInput = (
        .failed = false
    )
    assume reader ::= $&stdin_storage
    result ::= read_line(.allocator = $&allocator_storage, .reader = $&stdin_storage)

    if is(.value = result, .variant = ..error) {
    } else {
        status_code = 1
        return
    }

    if is(.value = result ..error.reason, .variant = ..stream_read_failed) {
    } else {
        status_code = 2
        return
    }

    status_code = 0
}
