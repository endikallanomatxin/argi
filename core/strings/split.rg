-- The cursor owns no storage. Source and separator views retain their backing
-- lifetimes; advancing it does not invalidate previously returned segments.
StringSplitIterator : Type = (
    ._text: StringView
    ._separator: StringView
    ._start: UIntNative
    ._done: Bool
)

StringSplitIterator implements Iterator#(.t: StringView)

split(
    .self: StringView,
    .separator: StringView,
) -> (.result: Errable#(.t: StringSplitIterator, .reasons: (..empty_separator))) := {
    if separator.length == 0 {
        result = ..error(.reason = ..empty_separator)
        return
    }
    result = ..ok (._text = self, ._separator = separator, ._start = 0, ._done = false)
}

has_next(.self: &StringSplitIterator) -> (.ok: Bool) := {
    ok = self&._done == false
}

next(.self: $&StringSplitIterator) -> (.value: StringView) := {
    if self&._done { abort }
    start ::= self&._start
    remaining ::= _string_view_subrange(.self = self&._text, .start = start, .count = self&._text.length - start).view
    match find(.self = remaining, .pattern = self&._separator).index {
        ..none {
            value = remaining
            self&._done = true
        }
        ..some payload {
            value = _string_view_subrange(.self = self&._text, .start = start, .count = payload.value).view
            -- The matched separator lies inside the remaining extent, so
            -- both additions stay within the original text length.
            self&._start = start + payload.value + self&._separator.length
        }
    }
}
