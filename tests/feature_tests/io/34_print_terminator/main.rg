RecordingWriter : Type = (
    .expected: StringView
    .count: UIntNative = 0
    .flush_calls: UIntNative = 0
    .fail_at: UIntNative = 999
    .flush_failure: Bool = false
)

write_byte(.self: $&RecordingWriter, .byte: UInt8) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    if self&.count == self&.fail_at {
        if self&.flush_failure {
            result = ..error(.reason = ..stream_flush_failed)
        } else {
            result = ..error(.reason = ..stream_write_failed)
        }
        return
    }
    if self&.count >= self&.expected.length { abort }
    if byte != bytes_get(.view = &self&.expected, .index = self&.count).byte { abort }
    self&.count = self&.count + 1
    result = ..ok Void()
}

flush(.self: $&RecordingWriter) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    self&.flush_calls = self&.flush_calls + 1
    result = ..ok Void()
}

RecordingWriter implements Writer

main(.system: System) -> (.status_code: Int32 = 0) := {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    base ::= RecordingWriter(.expected = "a\nb<>c\r\nd\nd=.!x")
    assume writer ::= $&base

    unwrap_or_abort(print("a"))
    unwrap_or_abort(print("b", .terminator = ""))
    unwrap_or_abort(print("", .terminator = "<>"))
    unwrap_or_abort(print("c", .terminator = "\r\n"))
    owned := format("d") | unwrap_or_abort(_)
    unwrap_or_abort(print(&owned))
    unwrap_or_abort(print(&owned, .terminator = "="))
    unwrap_or_abort(write(.self = writer, .text = ".!"))
    if base.count != 14 or base.flush_calls != 0 { abort }

    -- A failure writing the value must not attempt its terminator.
    base.fail_at = base.count
    failed_value := print("x")
    if is(failed_value, .variant = ..error) {
        if failed_value..error.reason != ..stream_write_failed { abort }
    } else { abort }
    if base.count != 14 { abort }

    -- Empty text with an empty terminator makes no writer calls.
    unwrap_or_abort(print("", .terminator = ""))

    base.fail_at = base.count + 1
    failed_terminator := print("x")
    if is(failed_terminator, .variant = ..error) {
        if failed_terminator..error.reason != ..stream_write_failed { abort }
    } else { abort }
    if base.count != 15 { abort }

    -- A writer may flush as part of write_byte; retain that failure reason.
    base.flush_failure = true
    failed_flush := print("", .terminator = "!")
    if is(failed_flush, .variant = ..error) {
        if failed_flush..error.reason != ..stream_flush_failed { abort }
    } else { abort }
    if base.flush_calls != 0 { abort }
    unwrap_or_abort(flush(.self = writer))
    if base.flush_calls != 1 { abort }
}
