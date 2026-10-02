DummyWriter : Type = (
    .count: Int32 = 0
)

write_byte(.self: $&DummyWriter, .byte: UInt8) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    self&.count = self&.count + 1
    byte
    result = ..ok(.value = Void())
}

flush(.self: $&DummyWriter) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    self
    result = ..ok(.value = Void())
}

DummyWriter implements Writer

relay(.writer: $&Writer) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    write_byte(.self = writer, .byte = 65)
    result = ..ok(.value = Void())
}

main() -> (.status_code: Int32) := {
    writer ::= DummyWriter()
    relay(.writer = $&writer)
    status_code = 0
    if writer.count != 1 {
        status_code = 1
    }
}
