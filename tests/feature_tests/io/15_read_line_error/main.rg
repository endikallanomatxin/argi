DummyInput := (
    .failed : Bool = false
)

implement Reader#(DummyInput) (
    .read_byte = (.self: $&DummyInput) -> (
        .result : Errable#(.t: ReadByte, .reasons: (..stream_read_failed))
    ) {

        result = ..error(.reason = ..stream_read_failed)
    }
)

main := (.system: System) -> (.status_code: Int32) {

    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocator_concrete := $&allocator_storage
    virtual_allocator ::= to_virtual#(Allocator)(allocator_concrete)
    assume allocator := $&virtual_allocator

    stdin_storage :: DummyInput = (
        .failed = false
    )
    assume reader ::= $&stdin_storage
    result ::= read_line(.allocator = allocator, .reader = $&stdin_storage)

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
