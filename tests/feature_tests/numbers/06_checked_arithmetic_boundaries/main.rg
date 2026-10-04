expect_value(
        .actual   : Errable#(.t: Int16, .reasons: (..out_of_range)),
        .expected : Int16
    ) -> () := {
    match actual { ..ok value { if value != expected { abort } } ..error _ { abort } }
}

expect_range(.actual: Errable#(.t: Int16, .reasons: (..out_of_range))) -> () := {
    match actual {
        ..ok unexpected { abort } ..error error { if error.reason != ..out_of_range { abort } }
    }
}

expect_division(
        .actual   : Errable#(.t: Int16, .reasons: (..out_of_range, ..division_by_zero)),
        .expected : Int16
    ) -> () := {
    match actual { ..ok value { if value != expected { abort } } ..error _ { abort } }
}

expect_division_range(
        .actual : Errable#(.t: Int16, .reasons: (..out_of_range, ..division_by_zero))
    ) -> () := {
    match actual {
        ..ok unexpected { abort } ..error error { if error.reason != ..out_of_range { abort } }
    }
}

expect_zero(
        .actual : Errable#(.t: Int16, .reasons: (..out_of_range, ..division_by_zero))
    ) -> () := {
    match actual {
        ..ok unexpected { abort } ..error error { if error.reason != ..division_by_zero { abort } }
    }
}

expect_value(
        .actual   : Errable#(.t: Int32, .reasons: (..out_of_range)),
        .expected : Int32
    ) -> () := {
    match actual { ..ok value { if value != expected { abort } } ..error _ { abort } }
}

expect_range(.actual: Errable#(.t: Int32, .reasons: (..out_of_range))) -> () := {
    match actual {
        ..ok unexpected { abort } ..error error { if error.reason != ..out_of_range { abort } }
    }
}

expect_division(
        .actual   : Errable#(.t: Int32, .reasons: (..out_of_range, ..division_by_zero)),
        .expected : Int32
    ) -> () := {
    match actual { ..ok value { if value != expected { abort } } ..error _ { abort } }
}

expect_division_range(
        .actual : Errable#(.t: Int32, .reasons: (..out_of_range, ..division_by_zero))
    ) -> () := {
    match actual {
        ..ok unexpected { abort } ..error error { if error.reason != ..out_of_range { abort } }
    }
}

expect_zero(
        .actual : Errable#(.t: Int32, .reasons: (..out_of_range, ..division_by_zero))
    ) -> () := {
    match actual {
        ..ok unexpected { abort } ..error error { if error.reason != ..division_by_zero { abort } }
    }
}

expect_value(
        .actual   : Errable#(.t: Int64, .reasons: (..out_of_range)),
        .expected : Int64
    ) -> () := {
    match actual { ..ok value { if value != expected { abort } } ..error _ { abort } }
}

expect_range(.actual: Errable#(.t: Int64, .reasons: (..out_of_range))) -> () := {
    match actual {
        ..ok unexpected { abort } ..error error { if error.reason != ..out_of_range { abort } }
    }
}

expect_division(
        .actual   : Errable#(.t: Int64, .reasons: (..out_of_range, ..division_by_zero)),
        .expected : Int64
    ) -> () := {
    match actual { ..ok value { if value != expected { abort } } ..error _ { abort } }
}

expect_division_range(
        .actual : Errable#(.t: Int64, .reasons: (..out_of_range, ..division_by_zero))
    ) -> () := {
    match actual {
        ..ok unexpected { abort } ..error error { if error.reason != ..out_of_range { abort } }
    }
}

expect_zero(
        .actual : Errable#(.t: Int64, .reasons: (..out_of_range, ..division_by_zero))
    ) -> () := {
    match actual {
        ..ok unexpected { abort } ..error error { if error.reason != ..division_by_zero { abort } }
    }
}

expect_value(
        .actual   : Errable#(.t: UInt16, .reasons: (..out_of_range)),
        .expected : UInt16
    ) -> () := {
    match actual { ..ok value { if value != expected { abort } } ..error _ { abort } }
}

expect_range(.actual: Errable#(.t: UInt16, .reasons: (..out_of_range))) -> () := {
    match actual {
        ..ok unexpected { abort } ..error error { if error.reason != ..out_of_range { abort } }
    }
}

expect_division(
        .actual   : Errable#(.t: UInt16, .reasons: (..out_of_range, ..division_by_zero)),
        .expected : UInt16
    ) -> () := {
    match actual { ..ok value { if value != expected { abort } } ..error _ { abort } }
}

expect_division_range(
        .actual : Errable#(.t: UInt16, .reasons: (..out_of_range, ..division_by_zero))
    ) -> () := {
    match actual {
        ..ok unexpected { abort } ..error error { if error.reason != ..out_of_range { abort } }
    }
}

expect_zero(
        .actual : Errable#(.t: UInt16, .reasons: (..out_of_range, ..division_by_zero))
    ) -> () := {
    match actual {
        ..ok unexpected { abort } ..error error { if error.reason != ..division_by_zero { abort } }
    }
}

expect_value(
        .actual   : Errable#(.t: UInt32, .reasons: (..out_of_range)),
        .expected : UInt32
    ) -> () := {
    match actual { ..ok value { if value != expected { abort } } ..error _ { abort } }
}

expect_range(.actual: Errable#(.t: UInt32, .reasons: (..out_of_range))) -> () := {
    match actual {
        ..ok unexpected { abort } ..error error { if error.reason != ..out_of_range { abort } }
    }
}

expect_division(
        .actual   : Errable#(.t: UInt32, .reasons: (..out_of_range, ..division_by_zero)),
        .expected : UInt32
    ) -> () := {
    match actual { ..ok value { if value != expected { abort } } ..error _ { abort } }
}

expect_division_range(
        .actual : Errable#(.t: UInt32, .reasons: (..out_of_range, ..division_by_zero))
    ) -> () := {
    match actual {
        ..ok unexpected { abort } ..error error { if error.reason != ..out_of_range { abort } }
    }
}

expect_zero(
        .actual : Errable#(.t: UInt32, .reasons: (..out_of_range, ..division_by_zero))
    ) -> () := {
    match actual {
        ..ok unexpected { abort } ..error error { if error.reason != ..division_by_zero { abort } }
    }
}

expect_value(
        .actual   : Errable#(.t: UInt64, .reasons: (..out_of_range)),
        .expected : UInt64
    ) -> () := {
    match actual { ..ok value { if value != expected { abort } } ..error _ { abort } }
}

expect_range(.actual: Errable#(.t: UInt64, .reasons: (..out_of_range))) -> () := {
    match actual {
        ..ok unexpected { abort } ..error error { if error.reason != ..out_of_range { abort } }
    }
}

expect_division(
        .actual   : Errable#(.t: UInt64, .reasons: (..out_of_range, ..division_by_zero)),
        .expected : UInt64
    ) -> () := {
    match actual { ..ok value { if value != expected { abort } } ..error _ { abort } }
}

expect_division_range(
        .actual : Errable#(.t: UInt64, .reasons: (..out_of_range, ..division_by_zero))
    ) -> () := {
    match actual {
        ..ok unexpected { abort } ..error error { if error.reason != ..out_of_range { abort } }
    }
}

expect_zero(
        .actual : Errable#(.t: UInt64, .reasons: (..out_of_range, ..division_by_zero))
    ) -> () := {
    match actual {
        ..ok unexpected { abort } ..error error { if error.reason != ..division_by_zero { abort } }
    }
}

expect_value(
        .actual   : Errable#(.t: UIntNative, .reasons: (..out_of_range)),
        .expected : UIntNative
    ) -> () := {
    match actual { ..ok value { if value != expected { abort } } ..error _ { abort } }
}

expect_range(.actual: Errable#(.t: UIntNative, .reasons: (..out_of_range))) -> () := {
    match actual {
        ..ok unexpected { abort } ..error error { if error.reason != ..out_of_range { abort } }
    }
}

expect_division(
        .actual   : Errable#(.t: UIntNative, .reasons: (..out_of_range, ..division_by_zero)),
        .expected : UIntNative
    ) -> () := {
    match actual { ..ok value { if value != expected { abort } } ..error _ { abort } }
}

expect_division_range(
        .actual : Errable#(.t: UIntNative, .reasons: (..out_of_range, ..division_by_zero))
    ) -> () := {
    match actual {
        ..ok unexpected { abort } ..error error { if error.reason != ..out_of_range { abort } }
    }
}

expect_zero(
        .actual : Errable#(.t: UIntNative, .reasons: (..out_of_range, ..division_by_zero))
    ) -> () := {
    match actual {
        ..ok unexpected { abort } ..error error { if error.reason != ..division_by_zero { abort } }
    }
}

check_int16() -> () := {
    minimum :: Int16 = -32768
    maximum :: Int16 = 32767
    zero :: Int16 = 0
    one :: Int16 = 1
    two :: Int16 = 2
    negative_one :: Int16 = -1
    negative_two :: Int16 = -2
    expect_value(
        .actual   = checked_add(.left = maximum, .right = zero)
        .expected = maximum
    )
    expect_range(.actual = checked_add(.left = maximum, .right = one))
    expect_range(.actual = checked_subtract(.left = minimum, .right = one))
    expect_value(
        .actual   = checked_subtract(.left = maximum, .right = maximum)
        .expected = zero
    )
    expect_value(
        .actual   = checked_multiply(.left = minimum, .right = zero)
        .expected = zero
    )
    expect_value(
        .actual   = checked_multiply(.left = maximum, .right = one)
        .expected = maximum
    )
    expect_range(.actual = checked_multiply(.left = maximum, .right = two))
    expect_division(
        .actual   = checked_divide(.left = minimum, .right = one)
        .expected = minimum
    )
    expect_division(
        .actual   = checked_divide(.left = maximum, .right = maximum)
        .expected = one
    )
    expect_zero(.actual = checked_divide(.left = maximum, .right = zero))
    expect_zero(.actual = checked_divide(.left = zero, .right = zero))
    expect_value(
        .actual   = checked_multiply(.left = maximum / two, .right = two)
        .expected = [
            maximum
            - one
        ]
    )
    expect_value(
        .actual   = checked_add(.left = minimum, .right = maximum)
        .expected = negative_one
    )
    expect_range(.actual = checked_add(.left = minimum, .right = negative_one))
    expect_range(.actual = checked_subtract(.left = maximum, .right = negative_one))
    expect_value(
        .actual   = checked_subtract(.left = minimum, .right = minimum)
        .expected = zero
    )
    expect_value(
        .actual   = checked_subtract(.left = zero, .right = maximum)
        .expected = [
            minimum
            + one
        ]
    )
    expect_range(.actual = checked_multiply(.left = minimum, .right = negative_one))
    expect_range(.actual = checked_multiply(.left = negative_one, .right = minimum))
    expect_range(.actual = checked_multiply(.left = minimum, .right = two))
    expect_value(
        .actual   = checked_multiply(.left = minimum, .right = one)
        .expected = minimum
    )
    expect_value(
        .actual   = checked_multiply(.left = minimum / two, .right = two)
        .expected = minimum
    )
    expect_division_range(
        .actual = checked_divide(.left = minimum, .right = negative_one)
    )
    expect_division(
        .actual   = checked_divide(.left = minimum, .right = two)
        .expected = [
            minimum
            / two
        ]
    )
    expect_division(
        .actual   = checked_divide(.left = minimum, .right = minimum)
        .expected = one
    )
    expect_division(
        .actual   = checked_divide(.left = minimum, .right = negative_two)
        .expected = [
            maximum / two
            + one
        ]
    )
    expect_range(
        .actual = checked_multiply(.left = minimum / two, .right = negative_two)
    )
    expect_value(
        .actual   = checked_multiply(.left = minimum / two + one, .right = negative_two)
        .expected = [
            maximum
            - one
        ]
    )
}

check_int32() -> () := {
    minimum :: Int32 = -2147483648
    maximum :: Int32 = 2147483647
    zero :: Int32 = 0
    one :: Int32 = 1
    two :: Int32 = 2
    negative_one :: Int32 = -1
    negative_two :: Int32 = -2
    expect_value(
        .actual   = checked_add(.left = maximum, .right = zero)
        .expected = maximum
    )
    expect_range(.actual = checked_add(.left = maximum, .right = one))
    expect_range(.actual = checked_subtract(.left = minimum, .right = one))
    expect_value(
        .actual   = checked_subtract(.left = maximum, .right = maximum)
        .expected = zero
    )
    expect_value(
        .actual   = checked_multiply(.left = minimum, .right = zero)
        .expected = zero
    )
    expect_value(
        .actual   = checked_multiply(.left = maximum, .right = one)
        .expected = maximum
    )
    expect_range(.actual = checked_multiply(.left = maximum, .right = two))
    expect_division(
        .actual   = checked_divide(.left = minimum, .right = one)
        .expected = minimum
    )
    expect_division(
        .actual   = checked_divide(.left = maximum, .right = maximum)
        .expected = one
    )
    expect_zero(.actual = checked_divide(.left = maximum, .right = zero))
    expect_zero(.actual = checked_divide(.left = zero, .right = zero))
    expect_value(
        .actual   = checked_multiply(.left = maximum / two, .right = two)
        .expected = [
            maximum
            - one
        ]
    )
    expect_value(
        .actual   = checked_add(.left = minimum, .right = maximum)
        .expected = negative_one
    )
    expect_range(.actual = checked_add(.left = minimum, .right = negative_one))
    expect_range(.actual = checked_subtract(.left = maximum, .right = negative_one))
    expect_value(
        .actual   = checked_subtract(.left = minimum, .right = minimum)
        .expected = zero
    )
    expect_value(
        .actual   = checked_subtract(.left = zero, .right = maximum)
        .expected = [
            minimum
            + one
        ]
    )
    expect_range(.actual = checked_multiply(.left = minimum, .right = negative_one))
    expect_range(.actual = checked_multiply(.left = negative_one, .right = minimum))
    expect_range(.actual = checked_multiply(.left = minimum, .right = two))
    expect_value(
        .actual   = checked_multiply(.left = minimum, .right = one)
        .expected = minimum
    )
    expect_value(
        .actual   = checked_multiply(.left = minimum / two, .right = two)
        .expected = minimum
    )
    expect_division_range(
        .actual = checked_divide(.left = minimum, .right = negative_one)
    )
    expect_division(
        .actual   = checked_divide(.left = minimum, .right = two)
        .expected = [
            minimum
            / two
        ]
    )
    expect_division(
        .actual   = checked_divide(.left = minimum, .right = minimum)
        .expected = one
    )
    expect_division(
        .actual   = checked_divide(.left = minimum, .right = negative_two)
        .expected = [
            maximum / two
            + one
        ]
    )
    expect_range(
        .actual = checked_multiply(.left = minimum / two, .right = negative_two)
    )
    expect_value(
        .actual   = checked_multiply(.left = minimum / two + one, .right = negative_two)
        .expected = [
            maximum
            - one
        ]
    )
}

check_int64() -> () := {
    minimum :: Int64 = -9223372036854775808
    maximum :: Int64 = 9223372036854775807
    zero :: Int64 = 0
    one :: Int64 = 1
    two :: Int64 = 2
    negative_one :: Int64 = -1
    negative_two :: Int64 = -2
    expect_value(
        .actual   = checked_add(.left = maximum, .right = zero)
        .expected = maximum
    )
    expect_range(.actual = checked_add(.left = maximum, .right = one))
    expect_range(.actual = checked_subtract(.left = minimum, .right = one))
    expect_value(
        .actual   = checked_subtract(.left = maximum, .right = maximum)
        .expected = zero
    )
    expect_value(
        .actual   = checked_multiply(.left = minimum, .right = zero)
        .expected = zero
    )
    expect_value(
        .actual   = checked_multiply(.left = maximum, .right = one)
        .expected = maximum
    )
    expect_range(.actual = checked_multiply(.left = maximum, .right = two))
    expect_division(
        .actual   = checked_divide(.left = minimum, .right = one)
        .expected = minimum
    )
    expect_division(
        .actual   = checked_divide(.left = maximum, .right = maximum)
        .expected = one
    )
    expect_zero(.actual = checked_divide(.left = maximum, .right = zero))
    expect_zero(.actual = checked_divide(.left = zero, .right = zero))
    expect_value(
        .actual   = checked_multiply(.left = maximum / two, .right = two)
        .expected = [
            maximum
            - one
        ]
    )
    expect_value(
        .actual   = checked_add(.left = minimum, .right = maximum)
        .expected = negative_one
    )
    expect_range(.actual = checked_add(.left = minimum, .right = negative_one))
    expect_range(.actual = checked_subtract(.left = maximum, .right = negative_one))
    expect_value(
        .actual   = checked_subtract(.left = minimum, .right = minimum)
        .expected = zero
    )
    expect_value(
        .actual   = checked_subtract(.left = zero, .right = maximum)
        .expected = [
            minimum
            + one
        ]
    )
    expect_range(.actual = checked_multiply(.left = minimum, .right = negative_one))
    expect_range(.actual = checked_multiply(.left = negative_one, .right = minimum))
    expect_range(.actual = checked_multiply(.left = minimum, .right = two))
    expect_value(
        .actual   = checked_multiply(.left = minimum, .right = one)
        .expected = minimum
    )
    expect_value(
        .actual   = checked_multiply(.left = minimum / two, .right = two)
        .expected = minimum
    )
    expect_division_range(
        .actual = checked_divide(.left = minimum, .right = negative_one)
    )
    expect_division(
        .actual   = checked_divide(.left = minimum, .right = two)
        .expected = [
            minimum
            / two
        ]
    )
    expect_division(
        .actual   = checked_divide(.left = minimum, .right = minimum)
        .expected = one
    )
    expect_division(
        .actual   = checked_divide(.left = minimum, .right = negative_two)
        .expected = [
            maximum / two
            + one
        ]
    )
    expect_range(
        .actual = checked_multiply(.left = minimum / two, .right = negative_two)
    )
    expect_value(
        .actual   = checked_multiply(.left = minimum / two + one, .right = negative_two)
        .expected = [
            maximum
            - one
        ]
    )
}

check_uint16() -> () := {
    minimum :: UInt16 = 0
    maximum :: UInt16 = 65535
    zero :: UInt16 = 0
    one :: UInt16 = 1
    two :: UInt16 = 2
    expect_value(
        .actual   = checked_add(.left = maximum, .right = zero)
        .expected = maximum
    )
    expect_range(.actual = checked_add(.left = maximum, .right = one))
    expect_range(.actual = checked_subtract(.left = minimum, .right = one))
    expect_value(
        .actual   = checked_subtract(.left = maximum, .right = maximum)
        .expected = zero
    )
    expect_value(
        .actual   = checked_multiply(.left = minimum, .right = zero)
        .expected = zero
    )
    expect_value(
        .actual   = checked_multiply(.left = maximum, .right = one)
        .expected = maximum
    )
    expect_range(.actual = checked_multiply(.left = maximum, .right = two))
    expect_division(
        .actual   = checked_divide(.left = minimum, .right = one)
        .expected = minimum
    )
    expect_division(
        .actual   = checked_divide(.left = maximum, .right = maximum)
        .expected = one
    )
    expect_zero(.actual = checked_divide(.left = maximum, .right = zero))
    expect_zero(.actual = checked_divide(.left = zero, .right = zero))
    expect_value(
        .actual   = checked_multiply(.left = maximum / two, .right = two)
        .expected = [
            maximum
            - one
        ]
    )
}

check_uint32() -> () := {
    minimum :: UInt32 = 0
    maximum :: UInt32 = 4294967295
    zero :: UInt32 = 0
    one :: UInt32 = 1
    two :: UInt32 = 2
    expect_value(
        .actual   = checked_add(.left = maximum, .right = zero)
        .expected = maximum
    )
    expect_range(.actual = checked_add(.left = maximum, .right = one))
    expect_range(.actual = checked_subtract(.left = minimum, .right = one))
    expect_value(
        .actual   = checked_subtract(.left = maximum, .right = maximum)
        .expected = zero
    )
    expect_value(
        .actual   = checked_multiply(.left = minimum, .right = zero)
        .expected = zero
    )
    expect_value(
        .actual   = checked_multiply(.left = maximum, .right = one)
        .expected = maximum
    )
    expect_range(.actual = checked_multiply(.left = maximum, .right = two))
    expect_division(
        .actual   = checked_divide(.left = minimum, .right = one)
        .expected = minimum
    )
    expect_division(
        .actual   = checked_divide(.left = maximum, .right = maximum)
        .expected = one
    )
    expect_zero(.actual = checked_divide(.left = maximum, .right = zero))
    expect_zero(.actual = checked_divide(.left = zero, .right = zero))
    expect_value(
        .actual   = checked_multiply(.left = maximum / two, .right = two)
        .expected = [
            maximum
            - one
        ]
    )
}

check_uint64() -> () := {
    minimum :: UInt64 = 0
    maximum :: UInt64 = 18446744073709551615
    zero :: UInt64 = 0
    one :: UInt64 = 1
    two :: UInt64 = 2
    expect_value(
        .actual   = checked_add(.left = maximum, .right = zero)
        .expected = maximum
    )
    expect_range(.actual = checked_add(.left = maximum, .right = one))
    expect_range(.actual = checked_subtract(.left = minimum, .right = one))
    expect_value(
        .actual   = checked_subtract(.left = maximum, .right = maximum)
        .expected = zero
    )
    expect_value(
        .actual   = checked_multiply(.left = minimum, .right = zero)
        .expected = zero
    )
    expect_value(
        .actual   = checked_multiply(.left = maximum, .right = one)
        .expected = maximum
    )
    expect_range(.actual = checked_multiply(.left = maximum, .right = two))
    expect_division(
        .actual   = checked_divide(.left = minimum, .right = one)
        .expected = minimum
    )
    expect_division(
        .actual   = checked_divide(.left = maximum, .right = maximum)
        .expected = one
    )
    expect_zero(.actual = checked_divide(.left = maximum, .right = zero))
    expect_zero(.actual = checked_divide(.left = zero, .right = zero))
    expect_value(
        .actual   = checked_multiply(.left = maximum / two, .right = two)
        .expected = [
            maximum
            - one
        ]
    )
}

check_uintnative() -> () := {
    minimum :: UIntNative = 0
    maximum :: UIntNative = 0
    bytes ::= size_of(.type = UIntNative)
    index :: UIntNative = 0
    while index < bytes {
        maximum = maximum * 256 + 255
        index = index + 1
    }
    zero :: UIntNative = 0
    one :: UIntNative = 1
    two :: UIntNative = 2
    expect_value(
        .actual   = checked_add(.left = maximum, .right = zero)
        .expected = maximum
    )
    expect_range(.actual = checked_add(.left = maximum, .right = one))
    expect_range(.actual = checked_subtract(.left = minimum, .right = one))
    expect_value(
        .actual   = checked_subtract(.left = maximum, .right = maximum)
        .expected = zero
    )
    expect_value(
        .actual   = checked_multiply(.left = minimum, .right = zero)
        .expected = zero
    )
    expect_value(
        .actual   = checked_multiply(.left = maximum, .right = one)
        .expected = maximum
    )
    expect_range(.actual = checked_multiply(.left = maximum, .right = two))
    expect_division(
        .actual   = checked_divide(.left = minimum, .right = one)
        .expected = minimum
    )
    expect_division(
        .actual   = checked_divide(.left = maximum, .right = maximum)
        .expected = one
    )
    expect_zero(.actual = checked_divide(.left = maximum, .right = zero))
    expect_zero(.actual = checked_divide(.left = zero, .right = zero))
    expect_value(
        .actual   = checked_multiply(.left = maximum / two, .right = two)
        .expected = [
            maximum
            - one
        ]
    )
}

main() -> (.status_code: Int32 = 0) := {
    check_int16()
    check_int32()
    check_int64()
    check_uint16()
    check_uint32()
    check_uint64()
    check_uintnative()
}
