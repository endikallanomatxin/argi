-- Fixed base-65536 limbs describe exact decimal/binary rounding intervals
-- independently of the host library, locale, and allocator. Only the
-- initialized prefix is used; decimal parsing and formatting share them.
_FloatDecimalInteger: Type = (
    .words : [256]UInt32 = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    )
    .used : UIntNative = 1
)

_float_integer_multiply(.self: $&_FloatDecimalInteger, .factor: UInt32, .addend: UInt32 = 0) -> () := {
    carry :: UInt32 = addend
    index :: UIntNative = 0
    while index < self&.used {
        product ::= self&.words[index] * factor + carry
        self&.words[index] = product % 65536
        carry = product / 65536
        index = index + 1
    }
    if carry != 0 {
        if self&.used == 256 { abort }
        self&.words[self&.used] = carry
        self&.used = self&.used + 1
    }
}

_float_integer_compare(.left: &_FloatDecimalInteger, .right: &_FloatDecimalInteger) -> (.order: Int32) := {
    if left&.used < right&.used { order = -1 return }
    if left&.used > right&.used { order = 1 return }
    index :: UIntNative = left&.used
    while index > 0 {
        index = index - 1
        if left&.words[index] < right&.words[index] { order = -1 return }
        if left&.words[index] > right&.words[index] { order = 1 return }
    }
    order = 0
}

_float_integer_subtract(.self: $&_FloatDecimalInteger, .other: &_FloatDecimalInteger) -> () := {
    borrow :: UInt32 = 0
    index :: UIntNative = 0
    while index < self&.used {
        digit :: UInt32 = borrow
        if index < other&.used { digit = digit + other&.words[index] }
        current ::= self&.words[index]
        if current < digit {
            self&.words[index] = current + 65536 - digit
            borrow = 1
        } else {
            self&.words[index] = current - digit
            borrow = 0
        }
        index = index + 1
    }
    if borrow != 0 { abort }
    while self&.used > 1 and self&.words[self&.used - 1] == 0 {
        self&.used = self&.used - 1
    }
}

_float_integer_halve(.self: $&_FloatDecimalInteger) -> () := {
    index :: UIntNative = self&.used
    carry :: UInt32 = 0
    while index > 0 {
        index = index - 1
        current ::= self&.words[index]
        self&.words[index] = current / 2 + carry * 32768
        carry = current % 2
    }
    if self&.used > 1 and self&.words[self&.used - 1] == 0 { self&.used = self&.used - 1 }
}

_float_integer_nonzero(.self: &_FloatDecimalInteger) -> (.value: Bool) := {
    value = self&.used != 1 or self&.words[0] != 0
}

_float_integer_from_u64(.value: UInt64) -> (.integer: _FloatDecimalInteger) := {
    integer = _FloatDecimalInteger()
    remaining ::= value
    integer.used = 0
    while true {
        integer.words[integer.used] = unwrap_or_abort(.value = UInt32(.value = remaining % 65536)).result
        integer.used = integer.used + 1
        remaining = remaining / 65536
        if remaining == 0 { break }
    }
}

_float_integer_divide_ten(.self: $&_FloatDecimalInteger) -> (.remainder: UInt32) := {
    remainder = 0
    index ::= self&.used
    while index > 0 {
        index = index - 1
        current ::= remainder * 65536 + self&.words[index]
        self&.words[index] = current / 10
        remainder = current % 10
    }
    while self&.used > 1 and self&.words[self&.used - 1] == 0 { self&.used = self&.used - 1 }
}

_float_integer_add_multiple(.self: $&_FloatDecimalInteger, .other: &_FloatDecimalInteger,
    .factor : UInt32) -> () := {
    carry :: UInt32 = 0
    index :: UIntNative = 0
    while index < other&.used or index < self&.used or carry != 0 {
        if index == 256 { abort }
        current ::= carry
        if index < other&.used { current = current + other&.words[index] * factor }
        if index < self&.used { current = current + self&.words[index] }
        self&.words[index] = current % 65536
        carry = current / 65536
        index = index + 1
    }
    self&.used = index
    while self&.used > 1 and self&.words[self&.used - 1] == 0 { self&.used = self&.used - 1 }
}
