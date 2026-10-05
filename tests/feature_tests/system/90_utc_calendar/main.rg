roundtrip(.date: UtcDateTime) -> !Void = ..ok Void() := {
    stamp ::= unix_timestamp(.date = date)!
    actual ::= utc_date(.timestamp = stamp)!
    if [
        actual.year != date.year
        or actual.month != date.month
        or actual.day != date.day
        or actual.hour != date.hour
        or actual.minute != date.minute
        or actual.second != date.second
        or actual.nanoseconds != date.nanoseconds
    ] { abort }
}

main() -> !Void = ..ok Void() := {
    roundtrip(.date = UtcDateTime(.year = 1, .month = 1, .day = 1))!
    roundtrip(
        .date = UtcDateTime(
            .year        = 9999
            .month       = 12
            .day         = 31
            .hour        = 23
            .minute      = 59
            .second      = 59
            .nanoseconds = 999999999
        )
    )!
    roundtrip(.date = UtcDateTime(.year = 2000, .month = 2, .day = 29))!
    stamp ::= unix_timestamp(.date = UtcDateTime(.year = 1970, .month = 1, .day = 1))!
    if unix_seconds(.self = &stamp).value != 0 { abort }
    prior ::= utc_date(.timestamp = UnixTimestamp(.seconds = -1))!
    if prior.year != 1969 or prior.month != 12 or prior.day != 31 or prior.second != 59 { abort }
    if valid_utc_date(.date = UtcDateTime(.year = 1900, .month = 2, .day = 29)).ok { abort }
    if weekday(.date = UtcDateTime(.year = 1970, .month = 1, .day = 1))! != 4 { abort }
}
