-- ASCII operations classify bytes, not Unicode scalars. Case conversion
-- preserves punctuation, control bytes and all bytes outside ASCII.
ascii_is_ascii(.byte: UInt8) -> (.ok: Bool) := { ok = byte < 128 }

ascii_is_digit(.byte: UInt8) -> (.ok: Bool) := { ok = byte >= 48 and byte <= 57 }

ascii_is_lower(.byte: UInt8) -> (.ok: Bool) := { ok = byte >= 97 and byte <= 122 }

ascii_is_upper(.byte: UInt8) -> (.ok: Bool) := { ok = byte >= 65 and byte <= 90 }

ascii_is_alpha(.byte: UInt8) -> (.ok: Bool) := {
    ok = ascii_is_lower(.byte = byte).ok or ascii_is_upper(.byte = byte).ok
}

ascii_is_alphanumeric(.byte: UInt8) -> (.ok: Bool) := {
    ok = ascii_is_alpha(.byte = byte).ok or ascii_is_digit(.byte = byte).ok
}

ascii_is_whitespace(.byte: UInt8) -> (.ok: Bool) := {
    ok = byte == 32 or byte >= 9 and byte <= 13
}

ascii_to_lower(.byte: UInt8) -> (.value: UInt8) := {
    value = byte
    if ascii_is_upper(.byte = byte).ok { value = byte + 32 }
}

ascii_to_upper(.byte: UInt8) -> (.value: UInt8) := {
    value = byte
    if ascii_is_lower(.byte = byte).ok { value = byte - 32 }
}
