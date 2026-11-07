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
