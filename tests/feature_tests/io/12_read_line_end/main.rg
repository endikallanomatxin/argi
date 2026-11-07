DummyInput := (
    .done : Bool = false
)

implement Reader#(DummyInput) (
    .read_byte = (.self: $&DummyInput) -> (
        .result : Errable#(.t: ReadByte, .reasons: (..stream_read_failed))
    ) {

        result = ..ok ..end
    }
)

main := (.system: System) -> (.status_code: Int32) {

    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocator_concrete := $&allocator_storage
    virtual_allocator ::= Virtual#(Allocator)(allocator_concrete)
    assume allocator := virtual_allocator

    stdin_storage :: DummyInput = (
        .done = false
    )
    assume reader ::= $&stdin_storage
    result ::= read_line(.allocator = allocator, .reader = $&stdin_storage)

    match result {
        ..error _ {
            status_code = 1
        }
        ..ok ~line_result {
            match line_result {
                ..end {
                    status_code = 0
                }
                ..ok ~line_payload {
                    line ::= ~line_payload
                    deinit(.self = $&line)
                    status_code = 1
                }
            }
        }
    }
}
