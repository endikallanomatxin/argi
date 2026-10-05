-- Bounds stay in the operand domain; no widening or signedness change is needed.
integer_limits(.value: Int8) -> (.minimum: Int8, .maximum: Int8) := {
    minimum = -128
    maximum = 127
}

integer_limits(.value: Int16) -> (.minimum: Int16, .maximum: Int16) := {
    minimum = -32768
    maximum = 32767
}

integer_limits(.value: Int32) -> (.minimum: Int32, .maximum: Int32) := {
    minimum = -2147483648
    maximum = 2147483647
}

integer_limits(.value: Int64) -> (.minimum: Int64, .maximum: Int64) := {
    minimum = -9223372036854775808
    maximum = 9223372036854775807
}

integer_limits(.value: UInt8) -> (.minimum: UInt8, .maximum: UInt8) := {
    minimum = 0
    maximum = 255
}

integer_limits(.value: UInt16) -> (.minimum: UInt16, .maximum: UInt16) := {
    minimum = 0
    maximum = 65535
}

integer_limits(.value: UInt32) -> (.minimum: UInt32, .maximum: UInt32) := {
    minimum = 0
    maximum = 4294967295
}

integer_limits(.value: UInt64) -> (.minimum: UInt64, .maximum: UInt64) := {
    minimum = 0
    maximum = 18446744073709551615
}

integer_limits(.value: UIntNative) -> (.minimum: UIntNative, .maximum: UIntNative) := {
    minimum = 0
    maximum = 0
    bytes ::= size_of(.type = UIntNative)
    index :: UIntNative = 0

    while index < bytes {
        maximum = maximum * 256 + 255
        index = index + 1
    }
}

..division_by_zero

checked_add#(
        .t : Type: Int
    )(
        .left  : t,
        .right : t
    ) -> (
        .result : Errable#(.t: t, .reasons: (..out_of_range))
    ) := {
    bounds ::= integer_limits(.value = left)

    if right > 0 {
        if left > bounds.maximum - right {
            result = ..error(.reason = ..out_of_range)
            return
        }
    } else {
        if right < 0 and left < bounds.minimum - right {
            result = ..error(.reason = ..out_of_range)
            return
        }
    }

    result = ..ok left + right
}

checked_subtract#(
        .t : Type: Int
    )(
        .left  : t,
        .right : t
    ) -> (
        .result : Errable#(.t: t, .reasons: (..out_of_range))
    ) := {
    bounds ::= integer_limits(.value = left)

    if right > 0 {
        if left < bounds.minimum + right {
            result = ..error(.reason = ..out_of_range)
            return
        }
    } else {
        if right < 0 and left > bounds.maximum + right {
            result = ..error(.reason = ..out_of_range)
            return
        }
    }

    result = ..ok left - right
}

checked_multiply#(
        .t : Type: Int
    )(
        .left  : t,
        .right : t
    ) -> (
        .result : Errable#(.t: t, .reasons: (..out_of_range))
    ) := {
    bounds ::= integer_limits(.value = left)
    -- Divide a representable bound, never a potentially overflowing product.
    -- The negative pair uses maximum/right and avoids negating signed minima.
    if right > 0 {
        if left > 0 and left > bounds.maximum / right {
            result = ..error(.reason = ..out_of_range)
            return
        }
        if left < 0 and left < bounds.minimum / right {
            result = ..error(.reason = ..out_of_range)
            return
        }
    } else {
        if right < 0 {
            if left > 0 and right < bounds.minimum / left {
                result = ..error(.reason = ..out_of_range)
                return
            }
            if left < 0 and left < bounds.maximum / right {
                result = ..error(.reason = ..out_of_range)
                return
            }
        }
    }

    result = ..ok left * right
}

checked_divide#(
        .t : Type: Int
    )(
        .left  : t,
        .right : t
    ) -> (
        .result : Errable#(.t: t, .reasons: (..out_of_range, ..division_by_zero))
    ) := {
    if right == 0 {
        result = ..error(.reason = ..division_by_zero)
        return
    }

    bounds ::= integer_limits(.value = left)

    if bounds.minimum < 0 {
        -- Form -1 only in the signed domain, after the signedness check.
        negative_one :: t = 0
        negative_one = negative_one - 1
        if left == bounds.minimum and right == negative_one {
            result = ..error(.reason = ..out_of_range)
            return
        }
    }

    result = ..ok left / right
}
