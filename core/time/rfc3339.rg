..invalid_datetime

-- UTC RFC 3339 profile: YYYY-MM-DDTHH:MM:SS[.1..9 digits]Z. Numeric
-- timezone offsets and leap seconds require a separate timezone policy.
_date_digits(
        .text  : StringView,
        .start : UIntNative,
        .count : UIntNative
    ) -> (
        .result : Errable#(UInt32, (..invalid_datetime))
    ) := {
    value :: UInt32 = 0
    index :: UIntNative = 0

    while index < count {
        byte ::= bytes_get(.view = &text, .index = start + index).byte
        if byte < 48 or byte > 57 {
            result = ..error(.reason = ..invalid_datetime)
            return
        }
        value = value * 10 + UInt32(.value = byte - 48)
        index = index + 1
    }

    result = ..ok value
}

parse_utc(
        .text : StringView
    ) -> (
        .result : Errable#(UtcDateTime, (..invalid_datetime))
    ) := {
    if text.length < 20 or text.length > 30 {
        result = ..error(.reason = ..invalid_datetime)
        return
    }

    if [
        bytes_get(.view = &text, .index = 4).byte != 45
        or bytes_get(.view = &text, .index = 7).byte != 45
        or bytes_get(.view = &text, .index = 10).byte != 84
        or bytes_get(.view = &text, .index = 13).byte != 58
        or bytes_get(.view = &text, .index = 16).byte != 58
        or bytes_get(.view = &text, .index = text.length - 1).byte != 90
    ] {
        result = ..error(.reason = ..invalid_datetime)
        return
    }

    fraction :: UInt32 = 0

    if text.length != 20 {
        if text.length < 22 or bytes_get(.view = &text, .index = 19).byte != 46 {
            result = ..error(.reason = ..invalid_datetime)
            return
        }
        digits ::= text.length - 21
        fraction = _date_digits(.text = text, .start = 20, .count = digits)!
        while digits < 9 {
            fraction = fraction * 10
            digits = digits + 1
        }
    }

    date ::= UtcDateTime(
        .year = unwrap_or_abort(
            .value = Int32(.value = _date_digits(.text = text, .start = 0, .count = 4)!)
        )
        .month       = _date_digits(.text = text, .start = 5, .count = 2)!
        .day         = _date_digits(.text = text, .start = 8, .count = 2)!
        .hour        = _date_digits(.text = text, .start = 11, .count = 2)!
        .minute      = _date_digits(.text = text, .start = 14, .count = 2)!
        .second      = _date_digits(.text = text, .start = 17, .count = 2)!
        .nanoseconds = fraction
    )

    if valid_utc_date(.date = date).ok == false {
        result = ..error(.reason = ..invalid_datetime)
        return
    }

    result = ..ok date
}

_write_date_digits(
        .buffer : ArrayView#(.t: UInt8),
        .start  : UIntNative,
        .count  : UIntNative,
        .value  : UInt32
    ) -> () := {
    index ::= count
    remaining ::= value

    while index > 0 {
        index = index - 1
        target ::= unwrap_or_abort(.value = get_rw_ref($&buffer, .index = start + index))
        target&= unwrap_or_abort(.value = UInt8(.value = remaining % 10 + 48))
        remaining = remaining / 10
    }
}

-- Validate date and complete capacity before writing. Nonzero fractions use
-- nine digits, preserving every nanosecond without allocation or truncation.
format_utc_into(
        .date   : UtcDateTime,
        .buffer : ArrayView#(.t: UInt8)
    ) -> (
        .result : Errable#(UIntNative, (..invalid_datetime, ..out_of_bounds))
    ) := {
    if valid_utc_date(.date = date).ok == false {
        result = ..error(.reason = ..invalid_datetime)
        return
    }

    count :: UIntNative = 20

    if date.nanoseconds != 0 { count = 30 }
    if length(&buffer).count < count {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    skeleton: StringView = "0000-00-00T00:00:00.000000000Z"
    index :: UIntNative = 0

    while index < count {
        target ::= unwrap_or_abort(.value = get_rw_ref($&buffer, .index = index))
        target&= bytes_get(.view = &skeleton, .index = index).byte
        index = index + 1
    }

    target ::= unwrap_or_abort(.value = get_rw_ref($&buffer, .index = count - 1))
    target&= 90
    _write_date_digits(
        .buffer = buffer
        .start  = 0
        .count  = 4
        .value  = unwrap_or_abort(.value = UInt32(.value = date.year))
    )
    _write_date_digits(.buffer = buffer, .start = 5, .count = 2, .value = date.month)
    _write_date_digits(.buffer = buffer, .start = 8, .count = 2, .value = date.day)
    _write_date_digits(.buffer = buffer, .start = 11, .count = 2, .value = date.hour)
    _write_date_digits(.buffer = buffer, .start = 14, .count = 2, .value = date.minute)
    _write_date_digits(.buffer = buffer, .start = 17, .count = 2, .value = date.second)

    if count == 30 {
        _write_date_digits(.buffer = buffer, .start = 20, .count = 9, .value = date.nanoseconds)
    }

    result = ..ok count
}
