expect_range_error(.value: Errable#(.t: Duration, .reasons: (..out_of_range))) -> () := {
    if is(.value = value, .variant = ..error) {
        if value ..error.reason != ..out_of_range { abort }
    } else { abort }
}
main() -> (.status_code: Int32 = 0) := {
    zero ::= Duration(.nanoseconds = 0)
    maximum ::= Duration(.nanoseconds = 18446744073709551615)
    one ::= Duration(.nanoseconds = 1)
    if nanoseconds(.self = &maximum).value != 18446744073709551615 { abort }
    micros ::= unwrap_or_abort(.value = Duration(.microseconds = 18446744073709551)).result
    millis ::= unwrap_or_abort(.value = Duration(.milliseconds = 18446744073709)).result
    whole ::= unwrap_or_abort(.value = Duration(.seconds = 18446744073)).result
    if nanoseconds(.self = &micros).value != 18446744073709551000 { abort }
    if nanoseconds(.self = &millis).value != 18446744073709000000 { abort }
    if nanoseconds(.self = &whole).value != 18446744073000000000 { abort }
    expect_range_error(.value = Duration(.microseconds = 18446744073709552))
    expect_range_error(.value = Duration(.milliseconds = 18446744073710))
    expect_range_error(.value = Duration(.seconds = 18446744074))
    fraction ::= Duration(.nanoseconds = 1234567890)
    if microseconds(.self = &fraction).value != 1234567 { abort }
    if milliseconds(.self = &fraction).value != 1234 { abort }
    if seconds(.self = &fraction).value != 1 { abort }
    same ::= unwrap_or_abort(.value = add(.left = maximum, .right = zero)).result
    if same != maximum { abort }
    same_zero ::= unwrap_or_abort(.value = subtract(.left = maximum, .right = maximum)).result
    if same_zero != zero { abort }
    expect_range_error(.value = add(.left = maximum, .right = one))
    expect_range_error(.value = subtract(.left = zero, .right = one))
    below ::= unwrap_or_abort(.value = subtract(.left = maximum, .right = one)).result
    if compare(.left = below, .right = maximum).order != -1 { abort }
    if compare(.left = maximum, .right = below).order != 1 { abort }
    if compare(.left = maximum, .right = same).order != 0 { abort }
    copied ::= copy(.self = &fraction).value
    if copied != fraction { abort }
    since_epoch ::= UnixTimestamp(.seconds = 0)
    before_epoch ::= unwrap_or_abort(.value = UnixTimestamp(.seconds = -1, .nanoseconds = 999999999)).result
    oldest ::= UnixTimestamp(.seconds = -9223372036854775808)
    newest ::= unwrap_or_abort(.value = UnixTimestamp(.seconds = 9223372036854775807,
            .nanoseconds = 999999999)).result
    if unix_seconds(.self = &oldest).value != -9223372036854775808 { abort }
    if unix_seconds(.self = &newest).value != 9223372036854775807 { abort }
    if nanoseconds(.self = &newest).value != 999999999 { abort }
    if compare(.left = before_epoch, .right = since_epoch).order != -1 { abort }
    if compare(.left = oldest, .right = newest).order != -1 { abort }
    if compare(.left = newest, .right = oldest).order != 1 { abort }
    timestamp_copy ::= copy(.self = &before_epoch).value
    if timestamp_copy != before_epoch { abort }
    invalid ::= UnixTimestamp(.seconds = 0, .nanoseconds = 1000000000)
    if is(.value = invalid, .variant = ..error) {
        if invalid ..error.reason != ..out_of_range { abort }
    } else { abort }
}
