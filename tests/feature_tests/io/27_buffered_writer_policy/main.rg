RecordingWriter : Type = (
    .byte_calls: UIntNative = 0
    .flush_calls: UIntNative = 0
    .received: UIntNative = 0
    .last_byte: UInt8 = 64
    .fail_write: Bool = false
    .fail_flush: Bool = false
)

write_byte(.self: $&RecordingWriter, .byte: UInt8) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    if self&.fail_write {
        result = ..error(.reason = ..stream_write_failed)
        return
    }
    if self&.byte_calls < 5 and byte != self&.last_byte + 1 { abort }
    self&.byte_calls = self&.byte_calls + 1
    self&.received = self&.received + 1
    self&.last_byte = byte
    result = ..ok Void()
}

flush(.self: $&RecordingWriter) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    self&.flush_calls = self&.flush_calls + 1
    if self&.fail_flush {
        result = ..error(.reason = ..stream_flush_failed)
        return
    }
    result = ..ok Void()
}

RecordingWriter implements Writer

main(.system: System) -> (.status_code: Int32 = 0) := {
    base ::= RecordingWriter()
    bytes ::= zeroed#(.t: [4]UInt8)()
    buffered ::= BufferedWriter#(.base_type: RecordingWriter)(.base = $&base, .buffer = array_view(.array = $&bytes))
    assume writer ::= $&buffered
    unwrap_or_abort(.value = write_byte(.self = writer, .byte = 65))
    unwrap_or_abort(.value = write_byte(.self = writer, .byte = 66))
    if base.byte_calls != 0 { status_code = 1 return }
    unwrap_or_abort(.value = write_byte(.self = writer, .byte = 67))
    unwrap_or_abort(.value = write_byte(.self = writer, .byte = 68))
    if base.byte_calls != 4 or base.received != 4 or base.last_byte != 68 { status_code = 2 return }
    if buffered.length != 0 or base.flush_calls != 1 { status_code = 3 return }
    unwrap_or_abort(.value = print("E"))
    if base.byte_calls != 5 or base.received != 5 or base.last_byte != 69 or base.flush_calls != 2 { status_code = 4 return }
    base.fail_write = true
    unwrap_or_abort(.value = write_byte(.self = writer, .byte = 70))
    stalled ::= flush(.self = writer)
    if is(.value = stalled, .variant = ..error) {
        if stalled..error.reason != ..stream_write_failed { status_code = 5 return }
    } else { status_code = 6 return }
    if buffered.length != 0 { status_code = 7 return }
    base.fail_write = false
    base.fail_flush = true
    failed ::= flush(.self = writer)
    if is(.value = failed, .variant = ..error) {
        if failed..error.reason != ..stream_flush_failed { status_code = 8 return }
    } else { status_code = 9 return }
    base.fail_flush = false
    deinit(.self = $&buffered)
    -- The wrapper borrows its base and leaves it usable after cleanup.
    unwrap_or_abort(.value = write_byte(.self = $&base, .byte = 71))
    if base.received != 6 or base.last_byte != 71 { status_code = 10 return }
    -- Cleanup leaves caller-owned storage usable as well as the base writer.
    if bytes[0] != 70 { status_code = 11 return }
    bytes[0] = 0
    unbuffered ::= BufferedWriter#(.base_type: RecordingWriter)(
        .base = $&base,
        .buffer = array_view(.array = $&zeroed#(.t: [0]UInt8)()),
    )
    unwrap_or_abort(.value = write_byte(.self = $&unbuffered, .byte = 72))
    if base.received != 7 or base.last_byte != 72 or unbuffered.length != 0 { status_code = 12 }

}
