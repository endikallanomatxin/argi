-- Monotonic instants have an unspecified OS origin; only their difference is
-- meaningful. Private fields prevent mixing Unix time into this domain.
MonotonicInstant: Type = (._nanoseconds: UInt64)

implement ImplicitlyCopyable#(MonotonicInstant) ()

UnixTimestamp: Type = (._seconds: Int64, ._nanoseconds: UInt32)

implement ImplicitlyCopyable#(UnixTimestamp) ()

implement Init#(UnixTimestamp, (.seconds: Int64)) (
        .Result : Type = UnixTimestamp
        .init   = (
                .args : (.seconds: Int64)
            ) -> (
                .result : Result
            ) {
            seconds ::= args.seconds

            result = (._seconds = seconds, ._nanoseconds = 0)
        }
    )

unix_timestamp_precise(
        .seconds     : Int64,
        .nanoseconds : UInt32
    ) -> (
        .result : Errable#(UnixTimestamp, (..out_of_range))
    ) := {
    if nanoseconds >= 1000000000 {
        result = ..error(.reason = ..out_of_range)
        return
    }

    result = ..ok(._seconds = seconds, ._nanoseconds = nanoseconds)
}

unix_seconds(.self: &UnixTimestamp) -> (.value: Int64) := { value = self&._seconds }

_nanoseconds_UnixTimestamp(.self: &UnixTimestamp) -> (.value: UInt32) := {
    value = self&._nanoseconds
}

implement NanosecondCount#(UnixTimestamp) (
    .Count            : Type                       = UInt32
    .nanosecond_count = _nanoseconds_UnixTimestamp
)

elapsed(
        .start : MonotonicInstant,
        .end   : MonotonicInstant
    ) -> (
        .result : Errable#(Duration, (..out_of_range))
    ) := {
    if end._nanoseconds < start._nanoseconds {
        result = ..error(.reason = ..out_of_range)
        return
    }

    result = ..ok Duration(.nanoseconds = end._nanoseconds - start._nanoseconds)
}

implement Equal#(
    MonotonicInstant,
    MonotonicInstant,
    (.left: MonotonicInstant, .right: MonotonicInstant)
) (
    .equal = (.args: (.left: MonotonicInstant, .right: MonotonicInstant)) -> (.ok: Bool) {
        ok = args.left._nanoseconds == args.right._nanoseconds
    }
)

implement Equal#(UnixTimestamp, UnixTimestamp, (.left: UnixTimestamp, .right: UnixTimestamp)) (
    .equal = (.args: (.left: UnixTimestamp, .right: UnixTimestamp)) -> (.ok: Bool) {
        ok = [
            args.left._seconds == args.right._seconds
            and args.left._nanoseconds == args.right._nanoseconds
        ]
    }
)

_compare_MonotonicInstant(.left: MonotonicInstant, .right: MonotonicInstant) -> (.order: Int32 = 0) := {
    if left._nanoseconds < right._nanoseconds { order = -1 }
    if left._nanoseconds > right._nanoseconds { order = 1 }
}

implement TimeCompare#(MonotonicInstant) (.compare_value = _compare_MonotonicInstant)

_compare_UnixTimestamp(.left: UnixTimestamp, .right: UnixTimestamp) -> (.order: Int32 = 0) := {
    if [
        left._seconds < right._seconds
        or [left._seconds == right._seconds and left._nanoseconds < right._nanoseconds]
    ] {
        order = -1
    }

    if [
        left._seconds > right._seconds
        or [left._seconds == right._seconds and left._nanoseconds > right._nanoseconds]
    ] {
        order = 1
    }
}

implement TimeCompare#(UnixTimestamp) (.compare_value = _compare_UnixTimestamp)

-- Clock carries permission to call the platform; pure time values carry none.
Clock: Type = (._ffi: $&ForeignFunctionInterface)

once _acquire_clock := (.args: (.ffi: $&ForeignFunctionInterface = reach ffi)) -> (.result: Clock) {
    ffi ::= args.ffi

    result = (._ffi = ffi)
}

implement Init#(Clock, (.ffi: $&ForeignFunctionInterface = reach ffi)) (
    .Result : Type           = Clock
    .init   = _acquire_clock
)

monotonic_now(
        .self : &Clock = reach clock
    ) -> (
        .result : Errable#(MonotonicInstant, (..clock_read_failed, ..out_of_range))
    ) := {
    assume ffi ::= self&._ffi
    reading ::= _platform_monotonic()

    if reading.status != 0 {
        result = ..error(.reason = ..clock_read_failed)
        return
    }

    maximum: UInt64 = 18446744073709551615
    fraction ::= reading.nanoseconds | convert#(.to: UInt64)(_)

    if reading.nanoseconds >= 1000000000 or reading.seconds > [maximum - fraction] / 1000000000 {
        result = ..error(.reason = ..out_of_range)
        return
    }

    result = ..ok(._nanoseconds = reading.seconds * 1000000000 + fraction)
}

wall_now(
        .self : &Clock = reach clock
    ) -> (
        .result : Errable#(UnixTimestamp, (..clock_read_failed, ..out_of_range))
    ) := {
    assume ffi ::= self&._ffi
    reading ::= _platform_wall()

    if reading.status != 0 {
        result = ..error(.reason = ..clock_read_failed)
        return
    }

    if reading.nanoseconds >= 1000000000 {
        result = ..error(.reason = ..out_of_range)
        return
    }

    result = ..ok(._seconds = reading.seconds, ._nanoseconds = reading.nanoseconds)
}

sleep(
        .duration : Duration,
        .self     : &Clock    = reach clock
    ) -> (
        .result : Errable#(Void, (..sleep_failed))
    ) := {
    assume ffi ::= self&._ffi

    if duration._nanoseconds == 0 {
        result = ..ok Void()
        return
    }

    whole ::= duration._nanoseconds / 1000000000
    fraction ::= unwrap_or_abort(
        .value = [
            [duration._nanoseconds % 1000000000]
            | convert#(.to: UInt32)(_)
        ]
    ).result

    if _platform_sleep(.seconds = whole, .nanoseconds = fraction).status != 0 {
        result = ..error(.reason = ..sleep_failed)
        return
    }

    result = ..ok Void()
}
