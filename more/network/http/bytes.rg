_byte := (.bytes: ArrayView#(.t: UInt8), .index: UIntNative) -> (.value: UInt8) {
    value = unwrap_or_abort(.value = get(&bytes, .index = index))
}

_slice := (.bytes: ArrayView#(.t: UInt8), .start: UIntNative, .end: UIntNative) -> (
    .value : ArrayView#(.t: UInt8)
) {
    value = unwrap_or_abort(.value = slice(&bytes, .start = start, .count = [end - start]))
}

_lower := (.byte: UInt8) -> (.value: UInt8) {
    value = byte
    if byte >= 65 and byte <= 90 { value = byte + 32 }
}

_ascii_equal := (.bytes: ArrayView#(.t: UInt8), .text: StringView) -> (.ok: Bool = false) {
    size ::= length(&bytes).count
    if size != byte_length(&text).count { return }
    i :: UIntNative = 0
    while i < size {
        if [
            _lower(.byte = _byte(.bytes = bytes, .index = i).value).value
            != _lower(
                .byte = unwrap_or_abort(.value = bytes_get(.view = &text, .index = i))
            ).value
        ] { return }
        i = i + 1
    }
    ok = true
}

_token := (.byte: UInt8) -> (.ok: Bool) {
    ok = [
        [byte >= 48 and byte <= 57]
        or [byte >= 65 and byte <= 90]
        or [byte >= 97 and byte <= 122]
        or byte == 33
        or byte == 35
        or byte == 36
        or byte == 37
        or byte == 38
        or byte == 39
        or byte == 42
        or byte == 43
        or byte == 45
        or byte == 46
        or byte == 94
        or byte == 95
        or byte == 96
        or byte == 124
        or byte == 126
    ]
}
