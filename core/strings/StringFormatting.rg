-- Value and provider jointly select string formatting algorithms.
StringFormatting#(.Value: Type, .Provider: Type): Contract = (
    .append : (.out: $&String, .value: Value, .allocator: $&Provider) -> (
        .result : Errable#(Void, (..out_of_memory))
    )
    .render : (.value: Value, .allocator: $&Provider) -> (
        .result : Errable#(String, (..out_of_memory))
    )
)

format_into := #(.Value: Type, .Provider: Type: Allocator) (
    .out: $&String, .value: Value, .allocator: $&Provider = reach allocator
) -> (.result: Errable#(Void, (..out_of_memory))) {
    result = StringFormatting#(
        Value, Provider
    ).append(.out = out, .value = ~value, .allocator = allocator)
}

format := #(.Value: Type, .Provider: Type: Allocator) (
    .value: Value, .allocator: $&Provider = reach allocator
) -> (.result: Errable#(String, (..out_of_memory))) {
    result = ~StringFormatting#(Value, Provider).render(.value = ~value, .allocator = allocator)
}

implement#(.Provider: Type: Allocator) StringFormatting#(StringView, Provider) (
    .append = _format_text_into
    .render = _format_text_owned
)

implement#(.Provider: Type: Allocator) StringFormatting#(Bool, Provider) (
    .append = _format_bool_into
    .render = _format_bool_owned
)

implement#(.Provider: Type: Allocator) StringFormatting#(Int8, Provider) (
    .append = _format_integer_into
    .render = _format_integer_owned
)

implement#(.Provider: Type: Allocator) StringFormatting#(Int16, Provider) (
    .append = _format_integer_into
    .render = _format_integer_owned
)

implement#(.Provider: Type: Allocator) StringFormatting#(Int32, Provider) (
    .append = _format_integer_into
    .render = _format_integer_owned
)

implement#(.Provider: Type: Allocator) StringFormatting#(Int64, Provider) (
    .append = _format_integer_into
    .render = _format_integer_owned
)

implement#(.Provider: Type: Allocator) StringFormatting#(UInt8, Provider) (
    .append = _format_integer_into
    .render = _format_integer_owned
)

implement#(.Provider: Type: Allocator) StringFormatting#(UInt16, Provider) (
    .append = _format_integer_into
    .render = _format_integer_owned
)

implement#(.Provider: Type: Allocator) StringFormatting#(UInt32, Provider) (
    .append = _format_integer_into
    .render = _format_integer_owned
)

implement#(.Provider: Type: Allocator) StringFormatting#(UInt64, Provider) (
    .append = _format_integer_into
    .render = _format_integer_owned
)

implement#(.Provider: Type: Allocator) StringFormatting#(UIntNative, Provider) (
    .append = _format_integer_into
    .render = _format_integer_owned
)

implement#(.Provider: Type: Allocator) StringFormatting#(Float16, Provider) (
    .append = _format_float_into
    .render = _format_float_owned
)

implement#(.Provider: Type: Allocator) StringFormatting#(Float32, Provider) (
    .append = _format_float_into
    .render = _format_float_owned
)

implement#(.Provider: Type: Allocator) StringFormatting#(Float64, Provider) (
    .append = _format_float_into
    .render = _format_float_owned
)
