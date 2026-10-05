-- Tokens borrow the original text. Only ASCII whitespace separates tokens;
-- repeated separators never produce empty tokens.
StringWhitespaceIterator: Type = (._text: StringView, ._start: UIntNative)

StringWhitespaceIterator implements Iterator#(.t: StringView)
StringWhitespaceIterator implements Iterable#(.t: StringView)

-- Iteration copies the remaining cursor state and preserves source lifetimes.
to_iterator(.value: &StringWhitespaceIterator) -> (.iterator: StringWhitespaceIterator) := {
    iterator = (._text = value&._text, ._start = value&._start)
}

_whitespace_token_start(.text: StringView, .start: UIntNative) -> (.position: UIntNative) := {
    position = start
    while position < text.length {
        if ascii_is_whitespace(.byte = bytes_get(.view = &text, .index = position).byte).ok == false {
            return
        }
        position = position + 1
    }
}

split_whitespace(.self: StringView) -> (.iterator: StringWhitespaceIterator) := {
    iterator = (._text = self, ._start = 0)
}

has_next(.self: &StringWhitespaceIterator) -> (.ok: Bool) := {
    ok = [
        _whitespace_token_start(.text = self&._text, .start = self&._start).position
        < self&._text.length
    ]
}

next(.self: $&StringWhitespaceIterator) -> (.value: StringView) := {
    start ::= _whitespace_token_start(.text = self&._text, .start = self&._start).position
    if start == self&._text.length { abort }
    end ::= start
    while end < self&._text.length {
        if ascii_is_whitespace(.byte = bytes_get(.view = &self&._text, .index = end).byte).ok {
            break
        }
        end = end + 1
    }
    value = _string_view_subrange(.self = self&._text, .start = start, .count = end - start).view
    self&._start = end
}
