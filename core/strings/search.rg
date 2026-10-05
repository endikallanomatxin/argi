-- Compares a byte pattern within the recorded view extent. No reference is
-- formed for an empty pattern, including an empty view at its end.
_string_view_matches_at(
        .self    : StringView,
        .pattern : StringView,
        .start   : UIntNative,
    ) -> (
        .ok : Bool
    ) := {
    if start > self.length {
        ok = false
        return
    }

    if pattern.length > self.length - start {
        ok = false
        return
    }

    offset :: UIntNative = 0

    while offset < pattern.length {
        if [
            bytes_get(.view = &self, .index = start + offset).byte
            != bytes_get(.view = &pattern, .index = offset).byte
        ] {
            ok = false
            return
        }
        offset = offset + 1
    }

    ok = true
}

-- Returns the first matching byte offset. The empty pattern matches at zero.
-- Search is allocation-free; worst-case work is length times pattern length.
find(.self: StringView, .pattern: StringView) -> (.index: ?UIntNative) := {
    index = ..none

    if pattern.length > self.length { return }
    last ::= self.length - pattern.length
    start :: UIntNative = 0

    while true {
        if _string_view_matches_at(self, .pattern = pattern, .start = start).ok {
            index = ..some(.value = start)
            return
        }
        if start == last { return }
        start = start + 1
    }
}

contains(.self: StringView, .pattern: StringView) -> (.ok: Bool) := {
    position ::= find(self, .pattern = pattern).index
    ok = position ?
}

starts_with(.self: StringView, .pattern: StringView) -> (.ok: Bool) := {
    ok = _string_view_matches_at(self, .pattern = pattern, .start = 0).ok
}

ends_with(.self: StringView, .pattern: StringView) -> (.ok: Bool) := {
    if pattern.length > self.length {
        ok = false
        return
    }

    ok = _string_view_matches_at(
        self
        .pattern = pattern
        .start   = [
            self.length
            - pattern.length
        ]
    ).ok
}

-- Reverse search returns the last matching byte offset, including the extent
-- for an empty pattern. Check zero before decrementing the unsigned cursor.
find_last(.self: StringView, .pattern: StringView) -> (.index: ?UIntNative = ..none) := {
    if pattern.length > self.length { return }
    start ::= self.length - pattern.length

    while true {
        if _string_view_matches_at(self, .pattern = pattern, .start = start).ok {
            index = ..some(.value = start)
            return
        }
        if start == 0 { return }
        start = start - 1
    }
}
