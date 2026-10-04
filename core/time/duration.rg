-- Unsigned nanoseconds distinguish intervals from civil dates and never wrap.
Duration: Type = (._nanoseconds: UInt64)

Duration implements ImplicitlyCopyable

Duration init(.nanoseconds: UInt64) -> (.result: Duration) := {
    result = (._nanoseconds = nanoseconds)
}

_duration_checked(
        .value : Errable#(.t: UInt64, .reasons: (..out_of_range))
    ) -> (
        .result : Errable#(.t: Duration, .reasons: (..out_of_range))
    ) := {
    match value {
        ..ok nanoseconds { result = ..ok Duration(.nanoseconds = nanoseconds) }
        ..error error { result = ..error error }
    }
}

_duration_scaled(
        .value : UInt64,
        .scale : UInt64
    ) -> (
        .result : Errable#(.t: Duration, .reasons: (..out_of_range))
    ) := {
    result = _duration_checked(.value = checked_multiply(.left = value, .right = scale)).result
}

Duration init(
        .microseconds : UInt64
    ) -> (
        .result : Errable#(.t: Duration, .reasons: (..out_of_range))
    ) := {
    result = _duration_scaled(.value = microseconds, .scale = 1000).result
}

Duration init(
        .milliseconds : UInt64
    ) -> (
        .result : Errable#(.t: Duration, .reasons: (..out_of_range))
    ) := {
    result = _duration_scaled(.value = milliseconds, .scale = 1000000).result
}

Duration init(.seconds: UInt64) -> (.result: Errable#(.t: Duration, .reasons: (..out_of_range))) := {
    result = _duration_scaled(.value = seconds, .scale = 1000000000).result
}

nanoseconds(.self: &Duration) -> (.value: UInt64) := { value = self&._nanoseconds }

microseconds(.self: &Duration) -> (.value: UInt64) := { value = self&._nanoseconds / 1000 }

milliseconds(.self: &Duration) -> (.value: UInt64) := { value = self&._nanoseconds / 1000000 }

seconds(.self: &Duration) -> (.value: UInt64) := { value = self&._nanoseconds / 1000000000 }

add(
        .left  : Duration,
        .right : Duration
    ) -> (
        .result : Errable#(
            .t       : Duration,
            .reasons : (..out_of_range)
        )
    ) := {
    result = _duration_checked(
        .value = checked_add(.left = left._nanoseconds, .right = right._nanoseconds)
    ).result
}

subtract(
        .left  : Duration,
        .right : Duration
    ) -> (
        .result : Errable#(
            .t       : Duration,
            .reasons : (..out_of_range)
        )
    ) := {
    result = _duration_checked(
        .value = checked_subtract(.left = left._nanoseconds, .right = right._nanoseconds)
    ).result
}

operator == (.left: Duration, .right: Duration) -> (.ok: Bool) := {
    ok = left._nanoseconds == right._nanoseconds
}

operator != (.left: Duration, .right: Duration) -> (.ok: Bool) := {
    ok = left._nanoseconds != right._nanoseconds
}

compare(.left: Duration, .right: Duration) -> (.order: Int32 = 0) := {
    if left._nanoseconds < right._nanoseconds { order = -1 }
    if left._nanoseconds > right._nanoseconds { order = 1 }
}
