DummyInput := (
    .index : UIntNative = 0
)

implement Reader<DummyInput> (
    .read_byte = (.self: $&DummyInput) -> (
        .result: Errable<.t: ReadByte, .reasons: (..stream_read_failed)>
    ) {
        if self&.index < 20 {
            current ::= self&.index
            self&.index = current + 1
            result = ..ok ..ok 65
            return
        }

        if self&.index == 20 {
            self&.index = 21
            result = ..ok ..ok 10
            return
        }

        result = ..ok ..end
    }
)

main := (.system: System) -> (.status_code: Int32) {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    stdin_storage :: DummyInput = (
        .index = 0
    )
    assume reader ::= $&stdin_storage
    result ::= read_line(.allocator = $&allocator_storage, .reader = $&stdin_storage)

    match result {
        ..error _ {
            status_code = 1
        }
        ..ok ~outer {
            match outer {
                ..end {
                    status_code = 1
                }
                ..ok ~line_payload {
                    line ::= ~line_payload
                    if byte_length(&line).count != 20 {
                        status_code = 2
                        return
                    }

                    if capacity(.self = &line).count < 20 {
                        status_code = 3
                        return
                    }

                    if unwrap_or_abort(.value = bytes_get(.view = &line, .index = 0)) != 65 {
                        status_code = 4
                        return
                    }

                    if unwrap_or_abort(.value = bytes_get(.view = &line, .index = 19)) != 65 {
                        status_code = 5
                        return
                    }

                    deinit(.self = $&line)
                    status_code = 0
                }
            }
        }
    }
}
