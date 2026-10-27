-- Unsigned nanoseconds distinguish intervals from civil dates and never wrap.
Duration := (._nanoseconds: UInt64)

implement ImplicitlyCopyable#(Duration) ()

implement Init#(Duration) (
    .init = (.nanoseconds: UInt64) -> (.result: Duration) {
        _init_nanoseconds ::= nanoseconds

        result = (._nanoseconds = _init_nanoseconds)
    }
)

_duration_checked := (.value: Errable#(UInt64, (..out_of_range))) -> (
    .result : Errable#(Duration, (..out_of_range))
) {
    match value {
        ..ok nanoseconds { result = ..ok Duration(.nanoseconds = nanoseconds) }
        ..error error { result = ..error error }
    }
}

_duration_scaled := (.value: UInt64, .scale: UInt64) -> (
    .result : Errable#(Duration, (..out_of_range))
) {
    result = _duration_checked(.value = checked_multiply(.left = value, .right = scale)).result
}

duration_from_microseconds := (.microseconds: UInt64) -> (
    .result : Errable#(Duration, (..out_of_range))
) {
    result = _duration_scaled(.value = microseconds, .scale = 1000).result
}

duration_from_milliseconds := (.milliseconds: UInt64) -> (
    .result : Errable#(Duration, (..out_of_range))
) {
    result = _duration_scaled(.value = milliseconds, .scale = 1000000).result
}

duration_from_seconds := (.seconds: UInt64) -> (.result: Errable#(Duration, (..out_of_range))) {
    result = _duration_scaled(.value = seconds, .scale = 1000000000).result
}

_nanoseconds_Duration := (.self: &Duration) -> (.value: UInt64) { value = self&._nanoseconds }

implement NanosecondCount#(Duration) (
    .Count            : Type = UInt64
    .nanosecond_count = _nanoseconds_Duration
)

microseconds := (.self: &Duration) -> (.value: UInt64) { value = self&._nanoseconds / 1000 }

milliseconds := (.self: &Duration) -> (.value: UInt64) { value = self&._nanoseconds / 1000000 }

seconds := (.self: &Duration) -> (.value: UInt64) { value = self&._nanoseconds / 1000000000 }

add := (.left: Duration, .right: Duration) -> (.result: Errable#(Duration, (..out_of_range))) {
    result = _duration_checked(
        .value = checked_add(.left = left._nanoseconds, .right = right._nanoseconds)
    ).result
}

subtract := (.left: Duration, .right: Duration) -> (
    .result : Errable#(Duration, (..out_of_range))
) {
    result = _duration_checked(
        .value = checked_subtract(.left = left._nanoseconds, .right = right._nanoseconds)
    ).result
}

implement Equal#(Duration, Duration) (
    .equal = (.left: Duration, .right: Duration) -> (.ok: Bool) {
        ok = left._nanoseconds == right._nanoseconds
    }
)

_compare_Duration := (.left: Duration, .right: Duration) -> (.order: Int32 = 0) {
    if left._nanoseconds < right._nanoseconds { order = -1 }
    if left._nanoseconds > right._nanoseconds { order = 1 }
}

implement TimeCompare#(Duration) (.compare_value = _compare_Duration)
