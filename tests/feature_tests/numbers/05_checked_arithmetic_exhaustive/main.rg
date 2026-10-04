verify(
        .actual   : Errable#(.t: Int8, .reasons: (..out_of_range)),
        .expected : Int32,
        .minimum  : Int32,
        .maximum  : Int32
    ) -> () := {
    match actual {
        ..ok value {
            if expected < minimum or expected > maximum { abort }
            if Int32(.value = value) != expected { abort }
        }
        ..error error {
            if error.reason != ..out_of_range { abort }
            if expected >= minimum and expected <= maximum { abort }
        }
    }
}

verify(
        .actual   : Errable#(.t: UInt8, .reasons: (..out_of_range)),
        .expected : Int32,
        .minimum  : Int32,
        .maximum  : Int32
    ) -> () := {
    match actual {
        ..ok value {
            if expected < minimum or expected > maximum { abort }
            if Int32(.value = value) != expected { abort }
        }
        ..error error {
            if error.reason != ..out_of_range { abort }
            if expected >= minimum and expected <= maximum { abort }
        }
    }
}

check_int8() -> () := {
    left :: Int32 = -128
    while left <= 127 {
        right :: Int32 = -128
        while right <= 127 {
            a ::= unwrap_or_abort(.value = Int8(.value = left)).result
            b ::= unwrap_or_abort(.value = Int8(.value = right)).result
            verify(
                .actual   = checked_add(.left = a, .right = b)
                .expected = left + right
                .minimum  = -128
                .maximum  = 127
            )
            verify(
                .actual   = checked_subtract(.left = a, .right = b)
                .expected = [
                    left
                    - right
                ]
                .minimum = -128
                .maximum = 127
            )
            verify(
                .actual   = checked_multiply(.left = a, .right = b)
                .expected = [
                    left
                    * right
                ]
                .minimum = -128
                .maximum = 127
            )
            match checked_divide(.left = a, .right = b) {
                ..ok value {
                    if right == 0 { abort }
                    expected ::= left / right
                    if expected < -128 or expected > 127 { abort }
                    if Int32(.value = value) != expected { abort }
                }
                ..error error {
                    if right == 0 {
                        if error.reason != ..division_by_zero { abort }
                    } else {
                        if left / right >= -128 and left / right <= 127 { abort }
                        if error.reason != ..out_of_range { abort }
                    }
                }
            }
            right = right + 1
        }
        left = left + 1
    }
}

check_uint8() -> () := {
    left :: Int32 = 0
    while left <= 255 {
        right :: Int32 = 0
        while right <= 255 {
            a ::= unwrap_or_abort(.value = UInt8(.value = left)).result
            b ::= unwrap_or_abort(.value = UInt8(.value = right)).result
            verify(
                .actual   = checked_add(.left = a, .right = b)
                .expected = [
                    left
                    + right
                ]
                .minimum = 0
                .maximum = 255
            )
            verify(
                .actual   = checked_subtract(.left = a, .right = b)
                .expected = [
                    left
                    - right
                ]
                .minimum = 0
                .maximum = 255
            )
            verify(
                .actual   = checked_multiply(.left = a, .right = b)
                .expected = [
                    left
                    * right
                ]
                .minimum = 0
                .maximum = 255
            )
            match checked_divide(.left = a, .right = b) {
                ..ok value {
                    if right == 0 { abort }
                    expected ::= left / right
                    if expected < 0 or expected > 255 { abort }
                    if Int32(.value = value) != expected { abort }
                }
                ..error error {
                    if right == 0 {
                        if error.reason != ..division_by_zero { abort }
                    } else {
                        if left / right >= 0 and left / right <= 255 { abort }
                        if error.reason != ..out_of_range { abort }
                    }
                }
            }
            right = right + 1
        }
        left = left + 1
    }
}

main() -> (.status_code: Int32 = 0) := {
    check_int8()
    check_uint8()
}
