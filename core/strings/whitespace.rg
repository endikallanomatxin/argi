-- Tokens borrow the original text. Only ASCII whitespace separates tokens;
-- repeated separators never produce empty tokens.
StringWhitespaceIterator: Type = (._text: StringView, ._start: UIntNative)

-- Iteration copies the remaining cursor state and preserves source lifetimes.

_whitespace_token_start(.text: StringView, .start: UIntNative) -> (.position: UIntNative) := {
    position = start

    while position < text._length {
        if [
            ascii_is_whitespace(.byte = bytes_get(.view = &text, .index = position).byte).ok
            == false
        ] {
            return
        }
        position = position + 1
    }
}

split_whitespace(.self: StringView) -> (.iterator: StringWhitespaceIterator) := {
    iterator = (._text = self, ._start = 0)
}

implement Iterable#(StringWhitespaceIterator) (
    .Item         : Type = StringView
    .IteratorType : Type = StringWhitespaceIterator

    .to_iterator = (.value: &StringWhitespaceIterator) -> (.iterator: StringWhitespaceIterator) {
        iterator = (._text = value&._text, ._start = value&._start)
    }
)

implement Iterator#(StringWhitespaceIterator) (
    .Item : Type = StringView

    .has_next = (.self: &StringWhitespaceIterator) -> (.ok: Bool) {
        ok = [
            _whitespace_token_start(.text = self&._text, .start = self&._start).position
            < self&._text._length
        ]
    }

    .next = (.self: $&StringWhitespaceIterator) -> (.value: StringView) {
        start ::= _whitespace_token_start(.text = self&._text, .start = self&._start).position

        if start == self&._text._length { abort }
        end ::= start

        while end < self&._text._length {
            if ascii_is_whitespace(
                .byte = bytes_get(.view = &self&._text, .index = end).byte
            ).ok {
                break
            }
            end = end + 1
        }

        value = _string_view_subrange(self&._text, .start = start, .count = end - start).view
        self&._start = end
    }
)
