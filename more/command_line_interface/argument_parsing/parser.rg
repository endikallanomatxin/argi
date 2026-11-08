..invalid_option
..missing_option_value

OptionToken := (.name: StringView, .value: ?StringView, .short: Bool)

implement ImplicitlyCopyable#(OptionToken) ()

Argument: Type = (..option OptionToken, ..positional StringView)

implement ImplicitlyCopyable#(Argument) ()

-- Tokenize options without a schema: --name=value, --name, short groups,
-- positionals, and --. Names and attached values borrow the source. Schema
-- validation belongs to callers; take_value consumes the next token verbatim,
-- so negative numeric values do not accidentally become options.
Parser := #(.t: Type: ArgumentSource#(t)) (
    ._source       : &t,
    ._index        : UIntNative,
    ._short_offset : UIntNative,
    ._positionals  : Bool
)

ParserInitArgs: Type = #(.t: Type: ArgumentSource#(t)) (.source: &t, .start: UIntNative = 0)

implement#(.t: Type: ArgumentSource#(t)) Init#(Parser#(.t: t), ParserInitArgs#(t)) (
    .Result : Type = Parser#(.t: t)

    .init = ParserInitArgs#(t) -> (.result: Result) {
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

next := #(.t: Type: ArgumentSource#(t)) (.self: $&Parser#(.t: t)) -> (
    .result : Errable#(?Argument, (..invalid_option, ..invalid_utf8, ..out_of_bounds))
) {

    while self&._index < ArgumentSource#().length(self&._source).count {
        text ::= ArgumentSource#().get(self&._source, .index = self&._index)!
        if self&._short_offset > 0 {
            if [bytes_get(.view = &text, .index = self&._short_offset)! >= 128] {
                result = ..error(.reason = ..invalid_option)
                return
            }
            name ::= slice(text, .start = self&._short_offset, .count = 1) handle ignored, value {
                abort
            }
            self&._short_offset = self&._short_offset + 1
            if self&._short_offset == byte_length(&text).count {
                self&._index = self&._index + 1
                self&._short_offset = 0
            }
            result = ..ok ..some(
                .value = ..option(.name = name, .value = ..none, .short = true)
            )
            return
        }
        self&._index = self&._index + 1
        if self&._positionals or byte_length(&text).count < 2 {
            result = ..ok ..some(.value = ..positional text)
            return
        }
        if bytes_get(.view = &text, .index = 0)! != 45 {
            result = ..ok ..some(.value = ..positional text)
            return
        }
        if text == "--" {
            self&._positionals = true
            continue
        }
        if bytes_get(.view = &text, .index = 1)! != 45 {
            self&._index = self&._index - 1
            self&._short_offset = 1
            continue
        }
        end ::= byte_length(&text).count
        index :: UIntNative = 2
        while index < byte_length(&text).count {
            if bytes_get(.view = &text, .index = index)! == 61 {
                end = index
                break
            }
            index = index + 1
        }
        if end == 2 {
            result = ..error(.reason = ..invalid_option)
            return
        }
        name ::= slice(text, .start = 2, .count = end - 2) handle ignored, value { abort }
        attached :: ?StringView = ..none
        if end < byte_length(&text).count {
            attached_text ::= slice(
                text, .start = [end + 1], .count = [byte_length(&text).count - end - 1]
            ) handle ignored, value { abort }
            attached = ..some(.value = attached_text)
        }
        result = ..ok ..some(
            .value = ..option(.name = name, .value = attached, .short = false)
        )
        return
    }

    result = ..ok ..none
}

take_value := #(.t: Type: ArgumentSource#(t)) (.self: $&Parser#(.t: t), .option: OptionToken) -> (
    .result : Errable#(StringView, (..missing_option_value, ..invalid_utf8, ..out_of_bounds))
) {

    match option.value { ..some entry {
            result = ..ok entry.value
            return
        } ..none {} }

    if self&._short_offset > 0 {
        text ::= ArgumentSource#().get(self&._source, .index = self&._index)!
        start ::= self&._short_offset
        if bytes_get(.view = &text, .index = start)! == 61 {
            start = [start + 1]
        }
        value ::= slice(text, .start = start, .count = [byte_length(&text).count - start]) handle ignored, recovered {
            abort
        }
        result = ..ok value
        self&._short_offset = 0
        self&._index = self&._index + 1
        return
    }

    if self&._index >= ArgumentSource#().length(self&._source).count {
        result = ..error(.reason = ..missing_option_value)
        return
    }

    result = ..ok ArgumentSource#().get(self&._source, .index = self&._index)!
    self&._index = self&._index + 1
}
