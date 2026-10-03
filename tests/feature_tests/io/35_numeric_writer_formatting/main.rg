RecordingWriter: Type = (
    .expected      : StringView
    .count         : UIntNative = 0
    .flush_calls   : UIntNative = 0
    .fail_at       : UIntNative = 999
    .flush_failure : Bool       = false
)
write_byte(.self: $&RecordingWriter, .byte: UInt8) -> (.result: Errable#(.t: Void,
        .reasons : (..stream_write_failed, ..stream_flush_failed))) := {
    if self&.count == self&.fail_at {
        if self&.flush_failure { result = ..error(.reason = ..stream_flush_failed) } else {
            result = ..error(.reason = ..stream_write_failed)
        }
        return
    }
    if self&.count >= self&.expected.length { abort }
    if byte != bytes_get(.view = &self&.expected, .index = self&.count).byte { abort }
    self&.count = self&.count + 1
    result = ..ok Void()
}
flush(.self: $&RecordingWriter) -> (.result: Errable#(.t: Void,
        .reasons : (..stream_write_failed, ..stream_flush_failed))) := {
    self&.flush_calls = self&.flush_calls + 1
    result = ..ok Void()
}
RecordingWriter implements Writer
expect_written#(.t: Type: Int)(.value: t, .expected: StringView) -> () := {
    base ::= RecordingWriter(.expected = expected)
    unwrap_or_abort(.value = format_into(.out = $&base, .value = value))
    if base.count != expected.length { abort }
    base.count = 0
    unwrap_or_abort(.value = write(.self = $&base, .value = value))
    if base.count != expected.length { abort }
    base.count = 0
    unwrap_or_abort(.value = print(.value = value, .writer = $&base, .terminator = ""))
    if base.count != expected.length or base.flush_calls != 0 { abort }
}
main() -> (.status_code: Int32 = 0) := {
    int80: Int8 = -128
    expect_written(.value = int80, .expected = "-128")
    int81: Int8 = 0
    expect_written(.value = int81, .expected = "0")
    int82: Int8 = 127
    expect_written(.value = int82, .expected = "127")
    int160: Int16 = -32768
    expect_written(.value = int160, .expected = "-32768")
    int161: Int16 = 0
    expect_written(.value = int161, .expected = "0")
    int162: Int16 = 32767
    expect_written(.value = int162, .expected = "32767")
    int320: Int32 = -2147483648
    expect_written(.value = int320, .expected = "-2147483648")
    int321: Int32 = 0
    expect_written(.value = int321, .expected = "0")
    int322: Int32 = 2147483647
    expect_written(.value = int322, .expected = "2147483647")
    int640: Int64 = -9223372036854775808
    expect_written(.value = int640, .expected = "-9223372036854775808")
    int641: Int64 = 0
    expect_written(.value = int641, .expected = "0")
    int642: Int64 = 9223372036854775807
    expect_written(.value = int642, .expected = "9223372036854775807")
    uint80: UInt8 = 0
    expect_written(.value = uint80, .expected = "0")
    uint81: UInt8 = 255
    expect_written(.value = uint81, .expected = "255")
    uint160: UInt16 = 0
    expect_written(.value = uint160, .expected = "0")
    uint161: UInt16 = 65535
    expect_written(.value = uint161, .expected = "65535")
    uint320: UInt32 = 0
    expect_written(.value = uint320, .expected = "0")
    uint321: UInt32 = 4294967295
    expect_written(.value = uint321, .expected = "4294967295")
    uint640: UInt64 = 0
    expect_written(.value = uint640, .expected = "0")
    uint641: UInt64 = 18446744073709551615
    expect_written(.value = uint641, .expected = "18446744073709551615")
    uintnative0: UIntNative = 0
    expect_written(.value = uintnative0, .expected = "0")
    uintnative1: UIntNative = 18446744073709551615
    expect_written(.value = uintnative1, .expected = "18446744073709551615")
    lines ::= RecordingWriter(.expected = "-105\n12<>0")
    assume writer ::= $&lines
    unwrap_or_abort(.value = print(-105))
    unwrap_or_abort(.value = print(12, .terminator = "<>"))
    unwrap_or_abort(.value = print(0, .terminator = ""))
    if lines.count != lines.expected.length or lines.flush_calls != 0 { abort }

    -- A value failure preserves the successful prefix and omits its terminator.
    partial ::= RecordingWriter(.expected = "12345", .fail_at = 2)
    failed ::= print(.value = 12345, .writer = $&partial)
    if is(.value = failed, .variant = ..error) {
        if failed ..error.reason != ..stream_write_failed { abort }
    } else { abort }
    if partial.count != 2 or partial.flush_calls != 0 { abort }
    first ::= RecordingWriter(.expected = "", .fail_at = 0, .flush_failure = true)
    first_failed ::= format_into(.out = $&first, .value = -1)
    if is(.value = first_failed, .variant = ..error) {
        if first_failed ..error.reason != ..stream_flush_failed { abort }
    } else { abort }
    if first.count != 0 { abort }
    suffix ::= RecordingWriter(.expected = "12345", .fail_at = 5, .flush_failure = true)
    suffix_failed ::= print(.value = 12345, .writer = $&suffix, .terminator = "!")
    if is(.value = suffix_failed, .variant = ..error) {
        if suffix_failed ..error.reason != ..stream_flush_failed { abort }
    } else { abort }
    if suffix.count != 5 or suffix.flush_calls != 0 { abort }
}
