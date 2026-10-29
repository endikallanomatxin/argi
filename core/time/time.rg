-- Monotonic instants have an unspecified OS origin; only their difference is
-- meaningful. Private fields prevent mixing Unix time into this domain.
MonotonicInstant := (._nanoseconds: UInt64)

implement ImplicitlyCopyable#(MonotonicInstant) ()

UnixTimestamp := (._seconds: Int64, ._nanoseconds: UInt32)

implement ImplicitlyCopyable#(UnixTimestamp) ()

UnixTimestampInitArgs: Type = (.seconds: Int64)

implement Init#(UnixTimestamp, UnixTimestampInitArgs) (
    .Result : Type = UnixTimestamp

    .init = UnixTimestampInitArgs -> (.result: Result) {
        _init_seconds ::= seconds

        result = (._seconds = _init_seconds, ._nanoseconds = 0)
    }
)

unix_timestamp_precise := (
    .seconds      : Int64,
    .nanoseconds  : UInt32,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(UnixTimestamp, (..out_of_range))) {
    assume error_tracer

    if nanoseconds >= 1000000000 {
        result = ..error(.reason = ..out_of_range)
        return
    }

    result = ..ok(._seconds = seconds, ._nanoseconds = nanoseconds)
}

unix_seconds := (.self: &UnixTimestamp) -> (.value: Int64) { value = self&._seconds }

_nanoseconds_UnixTimestamp := (.self: &UnixTimestamp) -> (.value: UInt32) {
    value = self&._nanoseconds
}

implement NanosecondCount#(UnixTimestamp) (
    .Count            : Type = UInt32
    .nanosecond_count = _nanoseconds_UnixTimestamp
)

elapsed := (
    .start        : MonotonicInstant,
    .end          : MonotonicInstant,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(Duration, (..out_of_range))) {
    assume error_tracer

    if end._nanoseconds < start._nanoseconds {
        result = ..error(.reason = ..out_of_range)
        return
    }

    result = ..ok Duration(.nanoseconds = end._nanoseconds - start._nanoseconds)
}

implement Equal#(MonotonicInstant, MonotonicInstant) (
    .equal = (.left: MonotonicInstant, .right: MonotonicInstant) -> (.ok: Bool) {
        ok = left._nanoseconds == right._nanoseconds
    }
)

implement Equal#(UnixTimestamp, UnixTimestamp) (
    .equal = (.left: UnixTimestamp, .right: UnixTimestamp) -> (.ok: Bool) {
        ok = [left._seconds == right._seconds and left._nanoseconds == right._nanoseconds]
    }
)

_compare_MonotonicInstant := (.left: MonotonicInstant, .right: MonotonicInstant) -> (
    .order : Int32 = 0
) {
    if left._nanoseconds < right._nanoseconds { order = -1 }
    if left._nanoseconds > right._nanoseconds { order = 1 }
}

implement TimeCompare#(MonotonicInstant) (.compare_value = _compare_MonotonicInstant)

_compare_UnixTimestamp := (.left: UnixTimestamp, .right: UnixTimestamp) -> (.order: Int32 = 0) {
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
Clock := (._ffi: $&ForeignFunctionInterface)

_ClockInitArgs := (.ffi: $&ForeignFunctionInterface)

_acquire_clock := once _ClockInitArgs -> (.result: Clock) {

    result = (._ffi = ffi)
}

ClockInitArgs: Type = _ClockInitArgs

implement Init#(Clock, ClockInitArgs) (
    .Result : Type = Clock

    .init = _acquire_clock
)

monotonic_now := (
    .self         : &Clock,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(MonotonicInstant, (..clock_read_failed, ..out_of_range))) {
    assume error_tracer

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

wall_now := (
    .self         : &Clock,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(UnixTimestamp, (..clock_read_failed, ..out_of_range))) {
    assume error_tracer

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

sleep := (
    .duration     : Duration,
    .self         : &Clock,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(Void, (..sleep_failed))) {
    assume error_tracer

    assume ffi ::= self&._ffi

    if duration._nanoseconds == 0 {
        result = ..ok Void()
        return
    }

    whole ::= duration._nanoseconds / 1000000000
    fraction ::= unwrap_or_abort(
        .value = [[duration._nanoseconds % 1000000000] | convert#(.to: UInt32)(_)]
    ).result

    if _platform_sleep(.seconds = whole, .nanoseconds = fraction).status != 0 {
        result = ..error(.reason = ..sleep_failed)
        return
    }

    result = ..ok Void()
}
