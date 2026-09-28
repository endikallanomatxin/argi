DummyOutput : Type = (
    .write_count: Int32 = 0,
    .flush_count: Int32 = 0
)

write_byte(.self: $&DummyOutput, .byte: UInt8) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    _ ::= byte
    self& = (
        .write_count = self&.write_count + 1,
        .flush_count = self&.flush_count,
    )
    result = ..ok(.value = Void())
}

flush(.self: $&DummyOutput) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    self& = (
        .write_count = self&.write_count,
        .flush_count = self&.flush_count + 1,
    )
    result = ..ok(.value = Void())
}

DummyOutput implements Writer

DummyInput : Type = (
    .index: UIntNative = 0
)

read_byte(.self: $&DummyInput) -> (.result: Errable#(.t: ReadByte, .reasons: (..stream_read_failed))) := {
    if self&.index == 0 {
        self& = (.index = 1)
        result = ..ok ..ok 79
        return
    }

    if self&.index == 1 {
        self& = (.index = 2)
        result = ..ok ..ok 75
        return
    }

    if self&.index == 2 {
        self& = (.index = 3)
        result = ..ok ..ok 10
        return
    }

    result = ..ok ..end
}

DummyInput implements Reader

main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator_storage ::= GeneralPurposeAllocator(.backing_allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    stdout_storage :: DummyOutput = DummyOutput()
    assume stdout ::= $&stdout_storage
    stderr_storage :: DummyOutput = DummyOutput()
    assume stderr ::= $&stderr_storage

    text ::= String(.length = 1)
    bytes_set(.string = $&text, .index = 0, .value = 65)
    view ::= as_view(.self = &text)

    print(view)
    flush()
    print_error(view)
    flush_error()

    if stdout_storage.write_count != 1 {
        status_code = 1
        return
    }

    if stdout_storage.flush_count != 2 {
        status_code = 2
        return
    }

    if stderr_storage.write_count != 1 {
        status_code = 3
        return
    }

    if stderr_storage.flush_count != 1 {
        status_code = 4
        return
    }

    stdin_storage :: DummyInput = (

        .index = 0
    )
    assume stdin ::= $&stdin_storage
    buffer ::= String(.allocator = $&allocator_storage, .capacity = 4)
    into_buffer ::= read_line_into_buffer($&buffer)
    if is(.value = into_buffer, .variant = ..ok) {
    } else {
        status_code = 5
        return
    }

    if buffer.length != 2 {
        status_code = 6
        return
    }

    if bytes_get(.string = &buffer, .index = 0).byte != 79 {
        status_code = 7
        return
    }

    if bytes_get(.string = &buffer, .index = 1).byte != 75 {
        status_code = 8
        return
    }

    deinit(.self = $&buffer, .allocator = $&allocator_storage)

    stdin_storage = (
        .index = 0
    )
    line_result ::= read_line()
    match line_result {
        ..error _ {
            status_code = 9
            return
        }
        ..ok ~ outer {
            match outer {
                ..end {
                    status_code = 9
                    return
                }
                ..ok ~ line_payload {
                    line ::= ~line_payload
                    if line.length != 2 {
                        status_code = 10
                        return
                    }

                    if bytes_get(.string = &line, .index = 0).byte != 79 {
                        status_code = 11
                        return
                    }

                    if bytes_get(.string = &line, .index = 1).byte != 75 {
                        status_code = 12
                        return
                    }

                    deinit(.self = $&line, .allocator = $&allocator_storage)
                }
            }
        }
    }
    deinit(.self = $&text, .allocator = $&allocator_storage)
}
