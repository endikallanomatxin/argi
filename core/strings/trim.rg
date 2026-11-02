-- Internal byte subranges are checked against the source view's recorded
-- extent. Empty results use static storage and form no one-past reference.
_string_view_subrange := (.self: StringView, .start: UIntNative, .count: UIntNative) -> (
    .view : StringView
) {
    if start > self._length { abort }
    if count > self._length - start { abort }
    if _string_boundary(.text = self, .offset = start).ok == false { abort }
    if _string_boundary(.text = self, .offset = start + count).ok == false { abort }
    if count == 0 {
        view = ""
        return
    }

    view = (
        ._data = trusted_reference_offset#(.t: UInt8)(
            .base = self._data, .elements = start
        ).reference
        ._length = count
    )
}

trim_start := (.self: StringView) -> (.view: StringView) {

    start :: UIntNative = 0

    while start < self._length {
        if [
            ascii_is_whitespace(
                .byte = unwrap_or_abort(.value = bytes_get(.view = &self, .index = start))
            ).ok
            == false
        ] { break }
        start = start + 1
    }

    view = _string_view_subrange(self, .start = start, .count = self._length - start).view
}

trim_end := (.self: StringView) -> (.view: StringView) {

    end :: UIntNative = self._length

    while end > 0 {
        if [
            ascii_is_whitespace(
                .byte = unwrap_or_abort(.value = bytes_get(.view = &self, .index = end - 1))
            ).ok
            == false
        ] { break }
        end = end - 1
    }

    view = _string_view_subrange(self, .start = 0, .count = end).view
}

trim := (.self: StringView) -> (.view: StringView) {
    leading ::= trim_start(self).view
    view = trim_end(leading).view
}

-- Validate by subtraction before forming a borrowed reference. Empty results
-- use static storage, including a slice at the source extent.
slice := (.self: StringView, .start: UIntNative, .count: UIntNative) -> (
    .result : Errable#(StringView, (..out_of_bounds, ..invalid_utf8_boundary))
) {

    if start > self._length {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    if count > self._length - start {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    if [
        _string_boundary(.text = self, .offset = start).ok == false
        or _string_boundary(.text = self, .offset = start + count).ok == false
    ] {
        result = ..error(.reason = ..invalid_utf8_boundary)
        return
    }
    result = ..ok _string_view_subrange(self, .start = start, .count = count).view
}

_string_boundary := (.text: StringView, .offset: UIntNative) -> (.ok: Bool) {

    if offset > text._length {
        ok = false
        return
    }
    if offset == text._length {
        ok = true
        return
    }
    byte ::= unwrap_or_abort(.value = bytes_get(.view = &text, .index = offset))
    ok = byte < 128 or byte >= 192
}
