-- Monotonic instants have an unspecified OS origin; only their difference is
-- meaningful. Private fields prevent mixing Unix time into this domain.
MonotonicInstant: Type = (._nanoseconds: UInt64)

MonotonicInstant implements ImplicitlyCopyable

UnixTimestamp: Type = (._seconds: Int64, ._nanoseconds: UInt32)

UnixTimestamp implements ImplicitlyCopyable

UnixTimestamp init(.seconds: Int64) -> (.result: UnixTimestamp) := {
    result = (._seconds = seconds, ._nanoseconds = 0)
}

UnixTimestamp init(
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

nanoseconds(.self: &UnixTimestamp) -> (.value: UInt32) := { value = self&._nanoseconds }

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

operator == (.left: MonotonicInstant, .right: MonotonicInstant) -> (.ok: Bool) := {
    ok = left._nanoseconds == right._nanoseconds
}

operator != (.left: MonotonicInstant, .right: MonotonicInstant) -> (.ok: Bool) := {
    ok = left._nanoseconds != right._nanoseconds
}

operator == (.left: UnixTimestamp, .right: UnixTimestamp) -> (.ok: Bool) := {
    ok = left._seconds == right._seconds and left._nanoseconds == right._nanoseconds
}

operator != (.left: UnixTimestamp, .right: UnixTimestamp) -> (.ok: Bool) := {
    ok = left._seconds != right._seconds or left._nanoseconds != right._nanoseconds
}

compare(.left: MonotonicInstant, .right: MonotonicInstant) -> (.order: Int32 = 0) := {
    if left._nanoseconds < right._nanoseconds { order = -1 }
    if left._nanoseconds > right._nanoseconds { order = 1 }
}

compare(.left: UnixTimestamp, .right: UnixTimestamp) -> (.order: Int32 = 0) := {
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

-- Clock carries permission to call the platform; pure time values carry none.
Clock: Type = (._ffi: $&ForeignFunctionInterface)

once Clock init(.ffi: $&ForeignFunctionInterface = reach ffi) -> (.result: Clock) := {
    result = (._ffi = ffi)
}

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
    fraction ::= UInt64(.value = reading.nanoseconds)

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
    fraction ::= unwrap_or_abort(.value = UInt32(.value = duration._nanoseconds % 1000000000)).result

    if _platform_sleep(.seconds = whole, .nanoseconds = fraction).status != 0 {
        result = ..error(.reason = ..sleep_failed)
        return
    }

    result = ..ok Void()
}
