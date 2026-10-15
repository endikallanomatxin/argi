-- Decimal integer encoding is shared with writer formatting.

decimal_digit_byte#(.t: Type: Int) := (.digit: t) -> (.byte: UInt8) {
    byte = _decimal_digit#(.t: t)(.digit = digit).byte
}

decimal_digit_byte_u32(.digit: UInt32) -> (.byte: UInt8) := {
    byte = _decimal_digit#(.t: UInt32)(.digit = digit).byte
}

decimal_digit_byte_i32(.digit: Int32) -> (.byte: UInt8) := {
    byte = _decimal_digit#(.t: Int32)(.digit = digit).byte
}

format_unsigned_decimal_into_u64#(
        .AllocatorType : Type: Allocator#(AllocatorType)
    )(
        .out       : $&String,
        .value     : UInt64,
        .allocator : $&AllocatorType
    ) -> (
        .result : Errable#(Void, (..out_of_memory))
    ) := {
    result = format_into(.out = out, .value = value, .allocator = allocator)
}

format_unsigned_decimal_into_u32#(
        .AllocatorType : Type: Allocator#(AllocatorType)
    )(
        .out       : $&String,
        .value     : UInt32,
        .allocator : $&AllocatorType
    ) -> (
        .result : Errable#(Void, (..out_of_memory))
    ) := {
    result = format_into(.out = out, .value = value, .allocator = allocator)
}

format_signed_decimal_into_i64#(
        .AllocatorType : Type: Allocator#(AllocatorType)
    )(
        .out       : $&String,
        .value     : Int64,
        .allocator : $&AllocatorType
    ) -> (
        .result : Errable#(Void, (..out_of_memory))
    ) := {
    result = format_into(.out = out, .value = value, .allocator = allocator)
}

format_signed_decimal_into_i32#(
        .AllocatorType : Type: Allocator#(AllocatorType)
    )(
        .out       : $&String,
        .value     : Int32,
        .allocator : $&AllocatorType
    ) -> (
        .result : Errable#(Void, (..out_of_memory))
    ) := {
    result = format_into(.out = out, .value = value, .allocator = allocator)
}

_format_text_into#(
        .Provider : Type: Allocator
    )(
        .out       : $&String,
        .value     : StringView,
        .allocator : $&Provider,
    ) -> (
        .result : Errable#(Void, (..out_of_memory))
    ) := {
    assume allocator

    result = push_view(out, .view = value)
}

_format_bool_into#(
        .Provider : Type: Allocator
    )(
        .out       : $&String,
        .value     : Bool,
        .allocator : $&Provider,
    ) -> (
        .result : Errable#(Void, (..out_of_memory))
    ) := {
    assume allocator

    if value {
        result = push_c_string(out, .text = "true")
    } else {
        result = push_c_string(out, .text = "false")
    }
}

_format_text_owned#(
        .Provider : Type: Allocator
    )(
        .value     : StringView,
        .allocator : $&Provider,
    ) -> (
        .result : Errable#(String, (..out_of_memory))
    ) := {
    assume allocator

    out ::= string_with_capacity(.capacity = value.length)!
    push_view($&out, .view = value)!

    result = ..ok ~out
}

_format_bool_owned#(
        .Provider : Type: Allocator
    )(
        .value     : Bool,
        .allocator : $&Provider,
    ) -> (
        .result : Errable#(String, (..out_of_memory))
    ) := {
    assume allocator

    out ::= string_with_capacity(.capacity = 5)!
    format_into(.out = $&out, .value = value)!

    result = ..ok ~out
}

_format_integer_into#(
        .t        : Type: Int,
        .Provider : Type: Allocator
    )(
        .out       : $&String,
        .value     : t,
        .allocator : $&Provider,
    ) -> (
        .result : Errable#(Void, (..out_of_memory))
    ) := {
    encoded ::= _decimal_encode#(.t: t)(.value = value)

    result = push_view(
        out
        .view      = _decimal_view(&encoded).view
        .allocator = allocator
    )
}

_format_integer_owned#(
        .t        : Type: Int,
        .Provider : Type: Allocator
    )(
        .value     : t,
        .allocator : $&Provider,
    ) -> (
        .result : Errable#(String, (..out_of_memory))
    ) := {
    assume allocator
    encoded ::= _decimal_encode#(.t: t)(.value = value)
    view ::= _decimal_view(&encoded).view

    result = format(.value = view, .allocator = allocator)
}

_format_float_into#(
        .t        : Type: Float,
        .Provider : Type: Allocator
    )(
        .out       : $&String,
        .value     : t,
        .allocator : $&Provider
    ) -> (
        .result : Errable#(Void, (..out_of_memory))
    ) := {
    encoded ::= _float_encode(.value = value)

    result = push_view(
        out
        .view      = _float_text_view(&encoded).view
        .allocator = allocator
    )
}

_format_float_owned#(
        .t        : Type: Float,
        .Provider : Type: Allocator
    )(
        .value     : t,
        .allocator : $&Provider
    ) -> (
        .result : Errable#(String, (..out_of_memory))
    ) := {
    assume allocator
    encoded ::= _float_encode(.value = value)

    result = format(.value = _float_text_view(&encoded).view, .allocator = allocator)
}
