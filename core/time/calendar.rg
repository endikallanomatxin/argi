-- Proleptic Gregorian UTC dates use years 1..9999 and seconds 0..59.
-- Leap seconds and local timezone rules are outside this representation.
UtcDateTime: Type = (
    .year        : Int32,
    .month       : UInt32,
    .day         : UInt32,
    .hour        : UInt32  = 0,
    .minute      : UInt32  = 0,
    .second      : UInt32  = 0,
    .nanoseconds : UInt32  = 0
)

UtcDateTime implements ImplicitlyCopyable

is_leap_year(.year: Int32) -> (.ok: Bool) := {
    ok = [
        year % 4 == 0
        and [year % 100 != 0 or year % 400 == 0]
    ]
}

days_in_month(.year: Int32, .month: UInt32) -> (.count: UInt32 = 0) := {
    if month < 1 or month > 12 { return }
    count = 31

    if month == 4 or month == 6 or month == 9 or month == 11 { count = 30 }
    if month == 2 {
        count = 28
        if is_leap_year(.year = year).ok { count = 29 }
    }
}

valid_utc_date(.date: UtcDateTime) -> (.ok: Bool) := {
    ok = [
        date.year >= 1
        and date.year <= 9999
        and date.month >= 1
        and date.month <= 12
        and date.day >= 1
        and date.day <= days_in_month(.year = date.year, .month = date.month).count
        and date.hour < 24
        and date.minute < 60
        and date.second < 60
        and date.nanoseconds < 1000000000
    ]
}

unix_timestamp(
        .date : UtcDateTime
    ) -> (
        .result : Errable#(UnixTimestamp, (..out_of_range))
    ) := {
    if valid_utc_date(.date = date).ok == false {
        result = ..error(.reason = ..out_of_range)
        return
    }

    previous ::= Int64(.value = date.year) - 1
    days ::= previous * 365 + previous / 4 - previous / 100 + previous / 400 - 719162
    month :: UInt32 = 1

    while month < date.month {
        days = [
            days
            + Int64(.value = days_in_month(.year = date.year, .month = month).count)
        ]
        month = [
            month
            + 1
        ]
    }

    days = days + Int64(.value = date.day) - 1
    seconds ::= [
        days * 86400
        + Int64(.value = date.hour) * 3600
        + Int64(.value = date.minute) * 60
        + Int64(.value = date.second)
    ]

    result = UnixTimestamp(.seconds = seconds, .nanoseconds = date.nanoseconds)
}

utc_date(
        .timestamp : UnixTimestamp
    ) -> (
        .result : Errable#(UtcDateTime, (..out_of_range))
    ) := {
    seconds ::= unix_seconds(.self = &timestamp).value

    if seconds < -62135596800 or seconds > 253402300799 {
        result = ..error(.reason = ..out_of_range)
        return
    }

    shifted ::= seconds + 62135596800
    days ::= shifted / 86400
    within ::= shifted % 86400
    cycles ::= days / 146097
    days = days % 146097
    year ::= unwrap_or_abort(.value = Int32(.value = cycles * 400 + 1))

    while true {
        year_days :: Int64 = 365
        if is_leap_year(.year = year).ok { year_days = 366 }
        if days < year_days { break }
        days = days - year_days
        year = year + 1
    }

    month :: UInt32 = 1

    while true {
        month_days ::= Int64(.value = days_in_month(.year = year, .month = month).count)
        if days < month_days { break }
        days = days - month_days
        month = month + 1
    }

    result = ..ok(
        .year  = year
        .month = month
        .day   = unwrap_or_abort(
            .value = UInt32(
                .value = [
                    days
                    + 1
                ]
            )
        )
        .hour = unwrap_or_abort(
            .value = UInt32(
                .value = [
                    within
                    / 3600
                ]
            )
        )
        .minute = unwrap_or_abort(
            .value = UInt32(
                .value = [
                    [within % 3600]
                    / 60
                ]
            )
        )
        .second = unwrap_or_abort(
            .value = UInt32(
                .value = [
                    within
                    % 60
                ]
            )
        )
        .nanoseconds = nanoseconds(.self = &timestamp).value
    )
}

-- Sunday is zero, matching conventional civil weekday numbering.
weekday(.date: UtcDateTime) -> (.result: Errable#(UInt32, (..out_of_range))) := {
    timestamp ::= unix_timestamp(.date = date)!
    days ::= [unix_seconds(.self = &timestamp).value + 62135596800] / 86400

    result = ..ok unwrap_or_abort(.value = UInt32(.value = [days + 1] % 7))
}
