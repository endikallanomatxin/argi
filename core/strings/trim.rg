-- Internal byte subranges are checked against the source view's recorded
-- extent. Empty results use static storage and form no one-past reference.
_string_view_subrange(
        .self  : StringView,
        .start : UIntNative,
        .count : UIntNative,
    ) -> (
        .view : StringView
    ) := {
    if start > self.length { abort }
    if count > self.length - start { abort }
    if count == 0 {
        view = ""
        return
    }
    view = (
        .data   = trusted_reference_offset#(.t: UInt8)(.base = self.data, .elements = start).reference
        .length = count
    )
}

_string_ascii_whitespace(.byte: UInt8) -> (.ok: Bool) := {
    ok = byte == 32 or byte >= 9 and byte <= 13
}

trim_start(.self: StringView) -> (.view: StringView) := {
    start :: UIntNative = 0
    while start < self.length {
        if [
            _string_ascii_whitespace(.byte = bytes_get(.view = &self, .index = start).byte).ok
            == false
        ] { break }
        start = start + 1
    }
    view = _string_view_subrange(.self = self, .start = start, .count = self.length - start).view
}

trim_end(.self: StringView) -> (.view: StringView) := {
    end :: UIntNative = self.length
    while end > 0 {
        if [
            _string_ascii_whitespace(.byte = bytes_get(.view = &self, .index = end - 1).byte).ok
            == false
        ] { break }
        end = end - 1
    }
    view = _string_view_subrange(.self = self, .start = 0, .count = end).view
}

trim(.self: StringView) -> (.view: StringView) := {
    leading ::= trim_start(.self = self).view
    view = trim_end(.self = leading).view
}
