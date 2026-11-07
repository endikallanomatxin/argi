Value := (.name: StringView, .value: ?StringView)

implement ImplicitlyCopyable#(Value) ()

Matches := (
    .options     : DynamicArray#(.t: Value),
    .positionals : DynamicArray#(.t: StringView)
)

Reasons: Type = (
    ..invalid_utf8,
    ..out_of_bounds,
    ..invalid_option,
    ..missing_option_value,
    ..unknown_option,
    ..duplicate_option,
    ..required_option,
    ..unexpected_option_value,
    ..invalid_cli_schema,
    ..out_of_memory
)

-- Names are canonical long option names, even when the user supplied an alias.
occurrences := (.self: &Matches, .name: StringView) -> (.count: UIntNative = 0) {
    for option in self&.options {
        if option.name == name { count = count + 1 }
    }
}

contains := (.self: &Matches, .name: StringView) -> (.ok: Bool) {
    ok = occurrences(self, name) > 0
}

value := (.self: &Matches, .name: StringView) -> (.text: ?StringView = ..none) {
    for option in self&.options {
        if option.name == name { text = option.value }
    }
}
