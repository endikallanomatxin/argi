-- The value type selects the string formatting algorithm.
StringFormatting#(.Value: Type): Contract = (
    .append : (.out: $&String, .value: Value, .allocator: $&Virtual#(Allocator)) -> (
        .result : Errable#(Void, (..out_of_memory))
    )
    .render : (.value: Value, .allocator: $&Virtual#(Allocator)) -> (
        .result : Errable#(String, (..out_of_memory))
    )
)

format_into := #(.Value: Type) (
    .out: $&String, .value: Value, .allocator: $&Virtual#(Allocator)
) -> (.result: Errable#(Void, (..out_of_memory))) {

    result = StringFormatting#(
        Value
    ).append(.out = out, .value = ~value, .allocator = allocator)
}

format := #(.Value: Type) (.value: Value, .allocator: $&Virtual#(Allocator)) -> (
    .result : Errable#(String, (..out_of_memory))
) {

    result = ~StringFormatting#(Value).render(.value = ~value, .allocator = allocator)
}

implement StringFormatting#(StringView) (
    .append = _format_text_into
    .render = _format_text_owned
)

implement StringFormatting#(Bool) (
    .append = _format_bool_into
    .render = _format_bool_owned
)

implement StringFormatting#(Int8) (
    .append = _format_integer_into
    .render = _format_integer_owned
)

implement StringFormatting#(Int16) (
    .append = _format_integer_into
    .render = _format_integer_owned
)

implement StringFormatting#(Int32) (
    .append = _format_integer_into
    .render = _format_integer_owned
)

implement StringFormatting#(Int64) (
    .append = _format_integer_into
    .render = _format_integer_owned
)

implement StringFormatting#(UInt8) (
    .append = _format_integer_into
    .render = _format_integer_owned
)

implement StringFormatting#(UInt16) (
    .append = _format_integer_into
    .render = _format_integer_owned
)

implement StringFormatting#(UInt32) (
    .append = _format_integer_into
    .render = _format_integer_owned
)

implement StringFormatting#(UInt64) (
    .append = _format_integer_into
    .render = _format_integer_owned
)

implement StringFormatting#(UIntNative) (
    .append = _format_integer_into
    .render = _format_integer_owned
)

implement StringFormatting#(Float16) (
    .append = _format_float_into
    .render = _format_float_owned
)

implement StringFormatting#(Float32) (
    .append = _format_float_into
    .render = _format_float_owned
)

implement StringFormatting#(Float64) (
    .append = _format_float_into
    .render = _format_float_owned
)
