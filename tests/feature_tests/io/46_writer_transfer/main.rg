Source: Type = (
    .bytes           : ArrayViewRO#(.t: UInt8)
    .position        : UIntNative              = 0
    .largest_request : UIntNative              = 0
    .fail            : Bool                    = false
    .fail_after      : UIntNative              = 999
)

Source implements BlockReader

read_block(
        .self   : $&Source,
        .buffer : ArrayView#(.t: UInt8)
    ) -> (
        .result : Errable#(UIntNative, (..stream_read_failed))
    ) := {
    size ::= length(&buffer).count
    if size > self&.largest_request { self&.largest_request = size }
    if self&.fail or self&.position == self&.fail_after {
        if size > 0 {
            target ::= unwrap_or_abort(.value = get_rw_ref($&buffer, 0))
            target&= 99
        }
        result = ..error(.reason = ..stream_read_failed)
        return
    }
    if self&.position == length(&self&.bytes).count {
        result = ..ok 0
        return
    }

    byte ::= unwrap_or_abort(.value = get_ro_ref(&self&.bytes, self&.position))
    target ::= unwrap_or_abort(.value = get_rw_ref($&buffer, 0))
    target&= byte&
    self&.position = self&.position + 1
    result = ..ok 1
}

FailingSink: Type = (.received: UIntNative = 0)

FailingSink implements Writer

write_byte(
        .self : $&FailingSink,
        .byte : UInt8
    ) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) := {
    self&.received = self&.received + 1
    result = ..ok Void()
}

flush(
        .self : $&FailingSink
    ) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) := {
    result = ..error(.reason = ..stream_flush_failed)
}

main() -> !Void = ..ok Void() := {
    input: [5]UInt8 = (0, 255, 65, 66, 10)
    output ::= zeroed#([8]UInt8)()
    base ::= ByteWriter(.bytes = view($&output))
    storage ::= zeroed#([3]UInt8)()
    writer ::= BufferedWriter(.base = $&base, .buffer = view($&storage))
    source ::= Source(.bytes = view(&input))

    write_byte($&writer, 80)!
    if transfer_stream(.writer = $&writer, .reader = $&source)! != 5 { abort }
    if source.largest_request != 3 { abort }
    flush($&writer)!
    if position(&base).count != 6 { abort }
    if output[0] != 80 or output[1] != 0 or output[2] != 255 { abort }
    if output[3] != 65 or output[4] != 66 or output[5] != 10 { abort }
    if transfer_stream(.writer = $&writer, .reader = $&source)! != 0 { abort }

    source.position = 0
    source.fail = true
    write_byte($&writer, 81)!
    match transfer_stream(.writer = $&writer, .reader = $&source) {
        ..ok _ { abort }
        ..error error { if error.reason != ..stream_read_failed { abort } }
    }
    flush($&writer)!
    if position(&base).count != 7 or output[6] != 81 { abort }

    source.fail = false
    fallback_output ::= zeroed#([5]UInt8)()
    fallback ::= ByteWriter(.bytes = view($&fallback_output))
    if transfer_stream(.writer = $&fallback, .reader = $&source)! != 5 { abort }
    if fallback_output[0] != 0 or fallback_output[1] != 255 or fallback_output[4] != 10 { abort }

    source.position = 0
    empty_storage ::= zeroed#([0]UInt8)()
    empty ::= view($&empty_storage)
    unbuffered_output ::= zeroed#([5]UInt8)()
    unbuffered_base ::= ByteWriter(.bytes = view($&unbuffered_output))
    unbuffered ::= BufferedWriter(.base = $&unbuffered_base, .buffer = empty)
    if transfer_stream(.writer = $&unbuffered, .reader = $&source)! != 5 { abort }
    if unbuffered_output[0] != 0 or unbuffered_output[1] != 255 or unbuffered_output[4] != 10 {
        abort
    }

    source.position = 0
    virtual ::= to_virtual#(.abstract: BlockReader)(.value = $&source)
    virtual_output ::= zeroed#([5]UInt8)()
    virtual_base ::= ByteWriter(.bytes = view($&virtual_output))
    virtual_storage ::= zeroed#([2]UInt8)()
    virtual_writer ::= BufferedWriter(.base = $&virtual_base, .buffer = view($&virtual_storage))
    if transfer_stream(.reader = $&virtual, .writer = $&virtual_writer)! != 5 { abort }
    flush($&virtual_writer)!
    if virtual_output[0] != 0 or virtual_output[1] != 255 or virtual_output[4] != 10 { abort }

    partial_source ::= Source(.bytes = view(&input), .fail_after = 2)
    partial_output ::= zeroed#([3]UInt8)()
    partial_base ::= ByteWriter(.bytes = view($&partial_output))
    partial_storage ::= zeroed#([3]UInt8)()
    partial_writer ::= BufferedWriter(.base = $&partial_base, .buffer = view($&partial_storage))
    match transfer_stream(.reader = $&partial_source, .writer = $&partial_writer) {
        ..ok _ { abort }
        ..error error { if error.reason != ..stream_read_failed { abort } }
    }
    if position(&partial_base).count != 0 { abort }
    flush($&partial_writer)!
    if position(&partial_base).count != 2 or partial_output[0] != 0 or partial_output[1] != 255 {
        abort
    }

    source.position = 0
    full ::= ByteWriter(.bytes = empty)
    blocked ::= BufferedWriter(.base = $&full, .buffer = view($&storage))
    match transfer_stream(.writer = $&blocked, .reader = $&source) {
        ..ok _ { abort }
        ..error error { if error.reason != ..stream_write_failed { abort } }
    }
    if source.position != 3 { abort }
    flush($&blocked)!

    flush_source ::= Source(.bytes = view(&input))
    flush_sink ::= FailingSink()
    flush_storage ::= zeroed#([2]UInt8)()
    flush_writer ::= BufferedWriter(.base = $&flush_sink, .buffer = view($&flush_storage))
    match transfer_stream(.reader = $&flush_source, .writer = $&flush_writer) {
        ..ok _ { abort }
        ..error error { if error.reason != ..stream_flush_failed { abort } }
    }
    if flush_source.position != 2 or flush_sink.received != 2 { abort }
    deinit($&flush_writer)
    if flush_sink.received != 2 { abort }

}
