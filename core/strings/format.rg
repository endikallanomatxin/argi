--
-- Baseline text formatting helpers.
--
-- v1 intentionally keeps formatting small and explicit:
-- it covers borrowed/owned text, booleans, and decimal integers.
-- Rich interpolation or printf-style formatting can be layered on top later.
-- The baseline intentionally sticks to the fixed-width integer overloads that
-- are exercised today. Reintroducing IntNative/UIntNative formatting should
-- wait until widening/conversion rules are explicit again instead of relying
-- on ad-hoc casts inside formatting helpers.
--

decimal_digit_byte(
    .digit: UInt64,
) -> (.byte: UInt8) := {
    if digit == 0 { byte = 48 return }
    if digit == 1 { byte = 49 return }
    if digit == 2 { byte = 50 return }
    if digit == 3 { byte = 51 return }
    if digit == 4 { byte = 52 return }
    if digit == 5 { byte = 53 return }
    if digit == 6 { byte = 54 return }
    if digit == 7 { byte = 55 return }
    if digit == 8 { byte = 56 return }
    byte = 57
}

decimal_digit_byte_u32(
    .digit: UInt32,
) -> (.byte: UInt8) := {
    if digit == 0 { byte = 48 return }
    if digit == 1 { byte = 49 return }
    if digit == 2 { byte = 50 return }
    if digit == 3 { byte = 51 return }
    if digit == 4 { byte = 52 return }
    if digit == 5 { byte = 53 return }
    if digit == 6 { byte = 54 return }
    if digit == 7 { byte = 55 return }
    if digit == 8 { byte = 56 return }
    byte = 57
}

decimal_digit_byte(
    .digit: Int64,
) -> (.byte: UInt8) := {
    if digit == 0 { byte = 48 return }
    if digit == 1 { byte = 49 return }
    if digit == 2 { byte = 50 return }
    if digit == 3 { byte = 51 return }
    if digit == 4 { byte = 52 return }
    if digit == 5 { byte = 53 return }
    if digit == 6 { byte = 54 return }
    if digit == 7 { byte = 55 return }
    if digit == 8 { byte = 56 return }
    byte = 57
}

decimal_digit_byte_i32(
    .digit: Int32,
) -> (.byte: UInt8) := {
    if digit == 0 { byte = 48 return }
    if digit == 1 { byte = 49 return }
    if digit == 2 { byte = 50 return }
    if digit == 3 { byte = 51 return }
    if digit == 4 { byte = 52 return }
    if digit == 5 { byte = 53 return }
    if digit == 6 { byte = 54 return }
    if digit == 7 { byte = 55 return }
    if digit == 8 { byte = 56 return }
    byte = 57
}

format_unsigned_decimal_into_u64(
    .out: $&String,
    .value: UInt64,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    if value == 0 {
        result = push_byte_growing(.self = out, .byte = 48, .allocator = allocator)
        return
    }

    reversed_result ::= string_with_capacity(.allocator = allocator, .capacity = 32)
    match reversed_result {
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
            return
        }
        ..ok ~ payload {
            reversed ::= payload.value
            current :: UInt64 = value

            while current > 0 {
                digit ::= current % 10
                pushed ::= push_byte_growing(.self = $&reversed, .byte = decimal_digit_byte_u32(.digit = digit).byte, .allocator = allocator)
                match pushed {
                    ..ok _ {
                    }
                    ..error _ {
                        deinit(.self = $&reversed, .allocator = allocator)
                        result = ..error(.reason = ..out_of_memory)
                        return
                    }
                }
                current = current / 10
            }

            i :: UIntNative = reversed.length
            while i > 0 {
                i = i - 1
                pushed ::= push_byte_growing(
                    .self = out,
                    .byte = bytes_get(.string = &reversed, .index = i).byte,
                    .allocator = allocator,
                )
                match pushed {
                    ..ok _ {
                    }
                    ..error _ {
                        deinit(.self = $&reversed, .allocator = allocator)
                        result = ..error(.reason = ..out_of_memory)
                        return
                    }
                }
            }

            deinit(.self = $&reversed, .allocator = allocator)
            result = ..ok(.value = Void())
        }
    }
}

format_unsigned_decimal_into_u32(
    .out: $&String,
    .value: UInt32,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    if value == 0 {
        result = push_byte_growing(.self = out, .byte = 48, .allocator = allocator)
        return
    }

    reversed_result ::= string_with_capacity(.allocator = allocator, .capacity = 16)
    match reversed_result {
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
            return
        }
        ..ok ~ payload {
            reversed ::= payload.value
            current :: UInt32 = value

            while current > 0 {
                digit ::= current % 10
                pushed ::= push_byte_growing(.self = $&reversed, .byte = decimal_digit_byte_u32(.digit = digit).byte, .allocator = allocator)
                match pushed {
                    ..ok _ {
                    }
                    ..error _ {
                        deinit(.self = $&reversed, .allocator = allocator)
                        result = ..error(.reason = ..out_of_memory)
                        return
                    }
                }
                current = current / 10
            }

            i :: UIntNative = reversed.length
            while i > 0 {
                i = i - 1
                pushed ::= push_byte_growing(
                    .self = out,
                    .byte = bytes_get(.string = &reversed, .index = i).byte,
                    .allocator = allocator,
                )
                match pushed {
                    ..ok _ {
                    }
                    ..error _ {
                        deinit(.self = $&reversed, .allocator = allocator)
                        result = ..error(.reason = ..out_of_memory)
                        return
                    }
                }
            }

            deinit(.self = $&reversed, .allocator = allocator)
            result = ..ok(.value = Void())
        }
    }
}

format_signed_decimal_into_i64(
    .out: $&String,
    .value: Int64,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    if value == 0 {
        result = push_byte_growing(.self = out, .byte = 48, .allocator = allocator)
        return
    }

    reversed_result ::= string_with_capacity(.allocator = allocator, .capacity = 32)
    match reversed_result {
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
            return
        }
        ..ok ~ payload {
            reversed ::= payload.value
            current :: Int64 = value

            if current < 0 {
                minus ::= push_byte_growing(.self = out, .byte = 45, .allocator = allocator)
                match minus {
                    ..ok _ {
                    }
                    ..error _ {
                        deinit(.self = $&reversed, .allocator = allocator)
                        result = ..error(.reason = ..out_of_memory)
                        return
                    }
                }
            }

            while current != 0 {
                remainder ::= current % 10
                if remainder < 0 {
                    remainder = 0 - remainder
                }

                pushed ::= push_byte_growing(
                    .self = $&reversed,
                    .byte = decimal_digit_byte_i32(.digit = remainder).byte,
                    .allocator = allocator,
                )
                match pushed {
                    ..ok _ {
                    }
                    ..error _ {
                        deinit(.self = $&reversed, .allocator = allocator)
                        result = ..error(.reason = ..out_of_memory)
                        return
                    }
                }
                current = current / 10
            }

            i :: UIntNative = reversed.length
            while i > 0 {
                i = i - 1
                pushed ::= push_byte_growing(
                    .self = out,
                    .byte = bytes_get(.string = &reversed, .index = i).byte,
                    .allocator = allocator,
                )
                match pushed {
                    ..ok _ {
                    }
                    ..error _ {
                        deinit(.self = $&reversed, .allocator = allocator)
                        result = ..error(.reason = ..out_of_memory)
                        return
                    }
                }
            }

            deinit(.self = $&reversed, .allocator = allocator)
            result = ..ok(.value = Void())
        }
    }
}

format_signed_decimal_into_i32(
    .out: $&String,
    .value: Int32,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    if value == 0 {
        result = push_byte_growing(.self = out, .byte = 48, .allocator = allocator)
        return
    }

    reversed_result ::= string_with_capacity(.allocator = allocator, .capacity = 16)
    match reversed_result {
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
            return
        }
        ..ok ~ payload {
            reversed ::= payload.value
            current :: Int32 = value

            if current < 0 {
                minus ::= push_byte_growing(.self = out, .byte = 45, .allocator = allocator)
                match minus {
                    ..ok _ {
                    }
                    ..error _ {
                        deinit(.self = $&reversed, .allocator = allocator)
                        result = ..error(.reason = ..out_of_memory)
                        return
                    }
                }
            }

            while current != 0 {
                remainder ::= current % 10
                if remainder < 0 {
                    remainder = 0 - remainder
                }

                pushed ::= push_byte_growing(
                    .self = $&reversed,
                    .byte = decimal_digit_byte_i32(.digit = remainder).byte,
                    .allocator = allocator,
                )
                match pushed {
                    ..ok _ {
                    }
                    ..error _ {
                        deinit(.self = $&reversed, .allocator = allocator)
                        result = ..error(.reason = ..out_of_memory)
                        return
                    }
                }
                current = current / 10
            }

            i :: UIntNative = reversed.length
            while i > 0 {
                i = i - 1
                pushed ::= push_byte_growing(
                    .self = out,
                    .byte = bytes_get(.string = &reversed, .index = i).byte,
                    .allocator = allocator,
                )
                match pushed {
                    ..ok _ {
                    }
                    ..error _ {
                        deinit(.self = $&reversed, .allocator = allocator)
                        result = ..error(.reason = ..out_of_memory)
                        return
                    }
                }
            }

            deinit(.self = $&reversed, .allocator = allocator)
            result = ..ok(.value = Void())
        }
    }
}

format_into(
    .out: $&String,
    .value: StringView,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    result = push_view_growing(.self = out, .view = &value, .allocator = allocator)
}

format_into(
    .out: $&String,
    .value: &StringView,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    result = push_view_growing(.self = out, .view = value, .allocator = allocator)
}

format_into(
    .out: $&String,
    .value: &String,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    view ::= as_view(.self = value)
    result = push_view_growing(.self = out, .view = &view, .allocator = allocator)
}

format_into(
    .out: $&String,
    .value: &Char,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    result = push_c_string_growing(.self = out, .text = value, .allocator = allocator)
}

format_into(
    .out: $&String,
    .value: Bool,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    if value {
        result = push_c_string_growing(.self = out, .text = "true", .allocator = allocator)
    } else {
        result = push_c_string_growing(.self = out, .text = "false", .allocator = allocator)
    }
}

format_into(
    .out: $&String,
    .value: UInt64,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    result = format_unsigned_decimal_into_u64(.out = out, .value = value, .allocator = allocator)
}

format_into(
    .out: $&String,
    .value: UInt32,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    result = format_unsigned_decimal_into_u32(.out = out, .value = value, .allocator = allocator)
}

format_into(
    .out: $&String,
    .value: Int64,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    result = format_signed_decimal_into_i64(.out = out, .value = value, .allocator = allocator)
}

format_into(
    .out: $&String,
    .value: Int32,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    result = format_signed_decimal_into_i32(.out = out, .value = value, .allocator = allocator)
}

format(
    .value: StringView,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: String, .reasons: (..out_of_memory))) := {
    create_result ::= string_with_capacity(.allocator = allocator, .capacity = value.length)
    match create_result {
        ..ok ~ payload {
            out ::= payload.value
            pushed ::= push_view_growing(.self = $&out, .view = &value, .allocator = allocator)
            match pushed {
                ..ok _ {
                    result = ..ok(.value = out)
                }
                ..error _ {
                    deinit(.self = $&out, .allocator = allocator)
                    result = ..error(.reason = ..out_of_memory)
                }
            }
        }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
        }
    }
}

format(
    .value: &StringView,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: String, .reasons: (..out_of_memory))) := {
    result = format(.value = value&, .allocator = allocator)
}

format(
    .value: &String,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: String, .reasons: (..out_of_memory))) := {
    view ::= as_view(.self = value)
    result = format(.value = view, .allocator = allocator)
}

format(
    .value: &Char,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: String, .reasons: (..out_of_memory))) := {
    length ::= c_string_length(.text = value).length
    create_result ::= string_with_capacity(.allocator = allocator, .capacity = length)
    match create_result {
        ..ok ~ payload {
            out ::= payload.value
            pushed ::= push_c_string_growing(.self = $&out, .text = value, .allocator = allocator)
            match pushed {
                ..ok _ {
                    result = ..ok(.value = out)
                }
                ..error _ {
                    deinit(.self = $&out, .allocator = allocator)
                    result = ..error(.reason = ..out_of_memory)
                }
            }
        }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
        }
    }
}

format(
    .value: Bool,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: String, .reasons: (..out_of_memory))) := {
    create_result ::= string_with_capacity(.allocator = allocator, .capacity = 5)
    match create_result {
        ..ok ~ payload {
            out ::= payload.value
            pushed ::= format_into(.out = $&out, .value = value, .allocator = allocator)
            match pushed {
                ..ok _ {
                    result = ..ok(.value = out)
                }
                ..error _ {
                    deinit(.self = $&out, .allocator = allocator)
                    result = ..error(.reason = ..out_of_memory)
                }
            }
        }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
        }
    }
}

format(
    .value: UInt64,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: String, .reasons: (..out_of_memory))) := {
    create_result ::= string_with_capacity(.allocator = allocator, .capacity = 32)
    match create_result {
        ..ok ~ payload {
            out ::= payload.value
            pushed ::= format_into(.out = $&out, .value = value, .allocator = allocator)
            match pushed {
                ..ok _ {
                    result = ..ok(.value = out)
                }
                ..error _ {
                    deinit(.self = $&out, .allocator = allocator)
                    result = ..error(.reason = ..out_of_memory)
                }
            }
        }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
        }
    }
}

format(
    .value: UInt32,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: String, .reasons: (..out_of_memory))) := {
    create_result ::= string_with_capacity(.allocator = allocator, .capacity = 16)
    match create_result {
        ..ok ~ payload {
            out ::= payload.value
            pushed ::= format_into(.out = $&out, .value = value, .allocator = allocator)
            match pushed {
                ..ok _ {
                    result = ..ok(.value = out)
                }
                ..error _ {
                    deinit(.self = $&out, .allocator = allocator)
                    result = ..error(.reason = ..out_of_memory)
                }
            }
        }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
        }
    }
}

format(
    .value: Int64,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: String, .reasons: (..out_of_memory))) := {
    create_result ::= string_with_capacity(.allocator = allocator, .capacity = 32)
    match create_result {
        ..ok ~ payload {
            out ::= payload.value
            pushed ::= format_into(.out = $&out, .value = value, .allocator = allocator)
            match pushed {
                ..ok _ {
                    result = ..ok(.value = out)
                }
                ..error _ {
                    deinit(.self = $&out, .allocator = allocator)
                    result = ..error(.reason = ..out_of_memory)
                }
            }
        }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
        }
    }
}

format(
    .value: Int32,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.result: Errable#(.t: String, .reasons: (..out_of_memory))) := {
    create_result ::= string_with_capacity(.allocator = allocator, .capacity = 16)
    match create_result {
        ..ok ~ payload {
            out ::= payload.value
            pushed ::= format_into(.out = $&out, .value = value, .allocator = allocator)
            match pushed {
                ..ok _ {
                    result = ..ok(.value = out)
                }
                ..error _ {
                    deinit(.self = $&out, .allocator = allocator)
                    result = ..error(.reason = ..out_of_memory)
                }
            }
        }
        ..error _ {
            result = ..error(.reason = ..out_of_memory)
        }
    }
}
