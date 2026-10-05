-- Decimal integer encoding is shared with writer formatting.

decimal_digit_byte(.digit: UInt64) -> (.byte: UInt8) := {
    byte = _decimal_digit#(.t: UInt64)(.digit = digit).byte
}

decimal_digit_byte_u32(.digit: UInt32) -> (.byte: UInt8) := {
    byte = _decimal_digit#(.t: UInt32)(.digit = digit).byte
}

decimal_digit_byte(.digit: Int64) -> (.byte: UInt8) := {
    byte = _decimal_digit#(.t: Int64)(.digit = digit).byte
}

decimal_digit_byte_i32(.digit: Int32) -> (.byte: UInt8) := {
    byte = _decimal_digit#(.t: Int32)(.digit = digit).byte
}

format_unsigned_decimal_into_u64(
        .out       : $&String,
        .value     : UInt64,
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(Void, (..out_of_memory))
    ) := {
    result = format_into(.out = out, .value = value, .allocator = allocator)
}

format_unsigned_decimal_into_u32(
        .out       : $&String,
        .value     : UInt32,
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(Void, (..out_of_memory))
    ) := {
    result = format_into(.out = out, .value = value, .allocator = allocator)
}

format_signed_decimal_into_i64(
        .out       : $&String,
        .value     : Int64,
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(Void, (..out_of_memory))
    ) := {
    result = format_into(.out = out, .value = value, .allocator = allocator)
}

format_signed_decimal_into_i32(
        .out       : $&String,
        .value     : Int32,
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(Void, (..out_of_memory))
    ) := {
    result = format_into(.out = out, .value = value, .allocator = allocator)
}

format_into(
        .out       : $&String,
        .value     : StringView,
        .allocator : $&Allocator,
    ) -> (
        .result : Errable#(Void, (..out_of_memory))
    ) := {
    assume allocator

    result = push_view(out, .view = value, .allocator = allocator)
}

format_into(
        .out       : $&String,
        .value     : Bool,
        .allocator : $&Allocator,
    ) -> (
        .result : Errable#(Void, (..out_of_memory))
    ) := {
    assume allocator

    if value {
        result = push_c_string(out, .text = "true", .allocator = allocator)
    } else {
        result = push_c_string(out, .text = "false", .allocator = allocator)
    }
}

format(
        .value     : StringView,
        .allocator : $&Allocator,
    ) -> (
        .result : Errable#(String, (..out_of_memory))
    ) := {
    assume allocator

    create_result ::= string_with_capacity(.allocator = allocator, .capacity = value.length)

    match create_result {
        ..ok ~view_output_payload {
            out ::= ~view_output_payload
            pushed ::= push_view($&out, .view = value, .allocator = allocator)
            if is(.value = pushed, .variant = ..error) {
                deinit(.self = $&out, .allocator = allocator)
                result = ..error(.reason = ..out_of_memory)
                return
            }
            result = ..ok ~out
        }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
        }
    }
}

format(
        .value     : Bool,
        .allocator : $&Allocator,
    ) -> (
        .result : Errable#(String, (..out_of_memory))
    ) := {
    assume allocator

    create_result ::= string_with_capacity(.allocator = allocator, .capacity = 5)

    match create_result {
        ..ok ~bool_output_payload {
            out ::= ~bool_output_payload
            pushed ::= format_into(.out = $&out, .value = value, .allocator = allocator)
            if is(.value = pushed, .variant = ..error) {
                deinit(.self = $&out, .allocator = allocator)
                result = ..error(.reason = ..out_of_memory)
                return
            }
            result = ..ok ~out
        }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
        }
    }
}

format_into#(
        .t : Type: Int
    )(
        .out       : $&String,
        .value     : t,
        .allocator : $&Allocator,
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

format#(
        .t : Type: Int
    )(
        .value     : t,
        .allocator : $&Allocator,
    ) -> (
        .result : Errable#(String, (..out_of_memory))
    ) := {
    assume allocator
    encoded ::= _decimal_encode#(.t: t)(.value = value)
    view ::= _decimal_view(&encoded).view

    result = format(.value = view, .allocator = allocator)
}

format_into#(
        .t : Type: Float
    )(
        .out       : $&String,
        .value     : t,
        .allocator : $&Allocator
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

format#(
        .t : Type: Float
    )(
        .value     : t,
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(String, (..out_of_memory))
    ) := {
    assume allocator
    encoded ::= _float_encode(.value = value)

    result = format(.value = _float_text_view(&encoded).view, .allocator = allocator)
}
