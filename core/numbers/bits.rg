-- Counts are native-sized. Zero has bit length zero and a full width of
-- leading/trailing zeros. Arithmetic stays within the unsigned operand type.
bit_length#(.t: Type: UInt)(.value: t) -> (.count: UIntNative = 0) := {
    remaining ::= value
    while remaining != 0 {
        count = count + 1
        remaining = remaining / 2
    }
}

count_ones#(.t: Type: UInt)(.value: t) -> (.count: UIntNative = 0) := {
    remaining ::= value
    while remaining != 0 {
        if remaining % 2 != 0 { count = count + 1 }
        remaining = remaining / 2
    }
}

count_leading_zeros#(.t: Type: UInt)(.value: t) -> (.count: UIntNative) := {
    count = size_of(.type = t) * 8 - bit_length#(.t: t)(.value = value).count
}

count_trailing_zeros#(.t: Type: UInt)(.value: t) -> (.count: UIntNative = 0) := {
    if value == 0 {
        count = size_of(.type = t) * 8
        return
    }
    remaining ::= value
    while remaining % 2 == 0 {
        count = count + 1
        remaining = remaining / 2
    }
}

reverse_bits#(.t: Type: UInt)(.value: t) -> (.result: t = 0) := {
    remaining ::= value
    width ::= size_of(.type = t) * 8
    index :: UIntNative = 0
    while index < width {
        result = result * 2 + remaining % 2
        remaining = remaining / 2
        index = index + 1
    }
}

is_power_of_two#(.t: Type: UInt)(.value: t) -> (.ok: Bool) := {
    ok = count_ones#(.t: t)(.value = value).count == 1
}
