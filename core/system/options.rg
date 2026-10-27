..invalid_option
..missing_option_value

CliOption := (.name: StringView, .value: ?StringView, .short: Bool)

implement ImplicitlyCopyable#(CliOption) ()

CliArgument: Type = (..option CliOption, ..positional StringView)

implement ImplicitlyCopyable#(CliArgument) ()

-- Tokenize options without a schema: --name=value, --name, short groups,
-- positionals, and --. Names and attached values borrow the source. Schema
-- validation belongs to callers; take_value consumes the next token verbatim,
-- so negative numeric values do not accidentally become options.
CliParser := #(.t: Type: ArgumentSource#(t)) (
    ._source       : &t,
    ._index        : UIntNative,
    ._short_offset : UIntNative,
    ._positionals  : Bool
)

implement#(.t: Type: ArgumentSource#(t)) Init#(CliParser#(.t: t)) (
    .init = (.source: &t, .start: UIntNative = 0) -> (.result: CliParser#(.t: t)) {
        _init_source ::= source
        _init_start ::= start

        result = (
            ._source       = _init_source
            ._index        = _init_start
            ._short_offset = 0
            ._positionals  = false
        )
    }
)

next := #(.t: Type: ArgumentSource#(t)) (.self: $&CliParser#(.t: t)) -> (
    .result : Errable#(?CliArgument, (..invalid_option, ..invalid_utf8, ..out_of_bounds))
) {
    while self&._index < length(self&._source).count {
        text ::= get(self&._source, .index = self&._index)!
        if self&._short_offset > 0 {
            if [
                unwrap_or_abort(.value = bytes_get(.view = &text, .index = self&._short_offset))
                >= 128
            ] {
                result = ..error(.reason = ..invalid_option)
                return
            }
            name ::= unwrap_or_abort(
                .value = slice(text, .start = self&._short_offset, .count = 1)
            )
            self&._short_offset = self&._short_offset + 1
            if self&._short_offset == text._length {
                self&._index = self&._index + 1
                self&._short_offset = 0
            }
            result = ..ok ..some(
                .value = ..option(.name = name, .value = ..none, .short = true)
            )
            return
        }
        self&._index = self&._index + 1
        if self&._positionals or text._length < 2 {
            result = ..ok ..some(.value = ..positional text)
            return
        }
        if unwrap_or_abort(.value = bytes_get(.view = &text, .index = 0)) != 45 {
            result = ..ok ..some(.value = ..positional text)
            return
        }
        if text == "--" {
            self&._positionals = true
            continue
        }
        if unwrap_or_abort(.value = bytes_get(.view = &text, .index = 1)) != 45 {
            self&._index = self&._index - 1
            self&._short_offset = 1
            continue
        }
        end ::= text._length
        index :: UIntNative = 2
        while index < text._length {
            if unwrap_or_abort(.value = bytes_get(.view = &text, .index = index)) == 61 {
                end = index
                break
            }
            index = index + 1
        }
        if end == 2 {
            result = ..error(.reason = ..invalid_option)
            return
        }
        name ::= unwrap_or_abort(.value = slice(text, .start = 2, .count = end - 2))
        attached :: ?StringView = ..none
        if end < text._length {
            attached = ..some(
                .value = unwrap_or_abort(
                    .value = slice(text, .start = [end + 1], .count = [text._length - end - 1])
                )
            )
        }
        result = ..ok ..some(
            .value = ..option(.name = name, .value = attached, .short = false)
        )
        return
    }

    result = ..ok ..none
}

take_value := #(.t: Type: ArgumentSource#(t)) (.self: $&CliParser#(.t: t), .option: CliOption) -> (
    .result : Errable#(StringView, (..missing_option_value, ..invalid_utf8, ..out_of_bounds))
) {
    match option.value { ..some entry {
            result = ..ok entry.value
            return
        } ..none {} }

    if self&._short_offset > 0 {
        text ::= get(self&._source, .index = self&._index)!
        start ::= self&._short_offset
        if unwrap_or_abort(.value = bytes_get(.view = &text, .index = start)) == 61 {
            start = [start + 1]
        }
        result = ..ok unwrap_or_abort(
            .value = slice(text, .start = start, .count = [text._length - start])
        )
        self&._short_offset = 0
        self&._index = self&._index + 1
        return
    }

    if self&._index >= length(self&._source).count {
        result = ..error(.reason = ..missing_option_value)
        return
    }

    result = ..ok get(self&._source, .index = self&._index)!
    self&._index = self&._index + 1
}
