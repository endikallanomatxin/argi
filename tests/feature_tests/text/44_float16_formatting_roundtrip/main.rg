DecimalBuffer: Type = (
    .bytes : [32]UInt8 = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0)
    .length : UIntNative = 0
)
write_byte(.self: $&DecimalBuffer, .byte: UInt8) -> (.result: Errable#(.t: Void,
        .reasons : (..stream_write_failed, ..stream_flush_failed))) := {
    if self&.length == 32 { abort }
    self&.bytes[self&.length] = byte
    self&.length = self&.length + 1
    result = ..ok Void()
}
flush(.self: $&DecimalBuffer) -> (.result: Errable#(.t: Void,
        .reasons : (..stream_write_failed, ..stream_flush_failed))) := {
    abort
}
DecimalBuffer implements Writer
main() -> (.status_code: Int32 = 0) := {
    index :: UInt32 = 0
    buffer ::= DecimalBuffer()
    -- Every finite binary16 encoding, including both zeros and all subnormals.
    while index < 65536 {
        bits ::= unwrap_or_abort(.value = UInt16(.value = index)).result
        if bits % 32768 < 31744 {
            original ::= trusted_reinterpret_reference#(.from: UInt16, .to: Float16)(.base = &bits).reference&
            buffer.length = 0
            unwrap_or_abort(.value = format_into(.out = $&buffer, .value = original))
            view :: StringView = (.data = &buffer.bytes[0], .length = buffer.length)
            parsed ::= unwrap_or_abort(.value = parse_float16(.text = view)).result
            parsed_bits ::= trusted_reinterpret_reference#(.from: Float16, .to: UInt16)(.base = &parsed).reference&
            if parsed_bits != bits { abort }
        }
        index = index + 1
    }
}
