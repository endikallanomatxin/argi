-- An owned buffer can cross a return boundary without borrowing its creator.
-- Twenty bytes cover every decimal UInt64 and Int64, including the sign.
_DecimalText: Type = (
    .bytes : [20]UInt8  = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    .start : UIntNative = 20
)

_decimal_digit#(.t: Type: Int)(.digit: t) -> (.byte: UInt8) := {
    if digit == 0 {
        byte = 48
        return
    }

    if digit == 1 {
        byte = 49
        return
    }

    if digit == 2 {
        byte = 50
        return
    }

    if digit == 3 {
        byte = 51
        return
    }

    if digit == 4 {
        byte = 52
        return
    }

    if digit == 5 {
        byte = 53
        return
    }

    if digit == 6 {
        byte = 54
        return
    }

    if digit == 7 {
        byte = 55
        return
    }

    if digit == 8 {
        byte = 56
        return
    }

    byte = 57
}

_decimal_encode#(.t: Type: Int)(.value: t) -> (.text: _DecimalText) := {
    text = _DecimalText()
    current :: t = value
    negative ::= current < 0

    while true {
        remainder ::= current % 10
        -- Only a remainder's magnitude is negated. The signed minimum itself
        -- never needs to fit in the positive range.
        if remainder < 0 { remainder = 0 - remainder }
        text.start = text.start - 1
        text.bytes[text.start] = _decimal_digit#(.t: t)(.digit = remainder).byte
        current = current / 10
        if current == 0 { break }
    }

    if negative {
        text.start = text.start - 1
        text.bytes[text.start] = 45
    }
}

_decimal_view(.self: &_DecimalText) -> (.view: StringView) := {
    view = (.data = &self&.bytes[self&.start], .length = 20 - self&.start)
}
