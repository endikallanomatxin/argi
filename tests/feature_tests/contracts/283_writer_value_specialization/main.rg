Counter := (.count: UIntNative = 0, .flushes: UIntNative = 0)

implement Writer#(Counter) (
    .write_byte = (.self: $&Counter, .byte: UInt8) -> (
        .result: Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) {
        self&.count = self&.count + 1
        result = ..ok Void()
    }
    .flush = (.self: $&Counter) -> (
        .result: Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) {
        self&.flushes = self&.flushes + 1
        result = ..ok Void()
    }
)

implement WriteValue#(Counter, Int32) (
    .Result      : Type = Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    .write_value = (.self: $&Counter, .value: Int32) -> (
        .result: Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) {
        self&.count = self&.count + 100
        result = ..ok Void()
    }
)

implement WriteValue#(Counter, Bool) (
    .Result      : Type = UIntNative
    .write_value = (.self: $&Counter, .value: Bool) -> (.result: UIntNative) {
        if value { self&.count = self&.count + 1 }
        result = self&.count
    }
)

send := #(.Stream: Type, .Value: Type) (.self: $&Stream, .value: Value) -> (
    .result: Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
) {
    result = WriteValue#(Stream, Value).write_value(.self = self, .value = value)
}

main := () -> (.status_code: Int32 = 0) {
    sink ::= Counter()
    unwrap_or_abort(.value = WriteValue#(Counter, Int32).write_value(.self = $&sink, .value = 7))
    unwrap_or_abort(.value = send(.self = $&sink, .value = 8))
    wide :: Int64 = 123
    unwrap_or_abort(.value = send(.self = $&sink, .value = wide))
    if sink.count != 203 or sink.flushes != 0 { status_code = 1 }
    {
        erased ::= to_virtual#(.contract: Writer)(.value = $&sink)
        unwrap_or_abort(.value = send(.self = $&erased, .value = 42))
    }
    if sink.count != 205 or sink.flushes != 0 { status_code = 2 }
    count ::= write(.self = $&sink, .value = true)
    if count != 206 { status_code = 3 }
    unwrap_or_abort(.value = write(.self = $&sink, .value = "abc"))
    if sink.count != 209 { status_code = 4 }
}
