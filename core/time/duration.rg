-- Unsigned nanoseconds distinguish intervals from civil dates and never wrap.
Duration: Type = (._nanoseconds: UInt64)
Duration implements ImplicitlyCopyable

Duration init(.nanoseconds: UInt64) -> (.result: Duration) := {
    result = (._nanoseconds = nanoseconds)
}
_duration_scaled(.value: UInt64, .scale: UInt64) -> (.result: Errable#(.t: Duration,
        .reasons : (..out_of_range))) := {
    maximum: UInt64 = 18446744073709551615
    if value > maximum / scale { result = ..error(.reason = ..out_of_range) return }
    result = ..ok Duration(.nanoseconds = value * scale)
}
Duration init(.microseconds: UInt64) -> (.result: Errable#(.t: Duration, .reasons: (..out_of_range))) := {
    result = _duration_scaled(.value = microseconds, .scale = 1000).result
}
Duration init(.milliseconds: UInt64) -> (.result: Errable#(.t: Duration, .reasons: (..out_of_range))) := {
    result = _duration_scaled(.value = milliseconds, .scale = 1000000).result
}
Duration init(.seconds: UInt64) -> (.result: Errable#(.t: Duration, .reasons: (..out_of_range))) := {
    result = _duration_scaled(.value = seconds, .scale = 1000000000).result
}
nanoseconds(.self: &Duration) -> (.value: UInt64) := { value = self&._nanoseconds }
microseconds(.self: &Duration) -> (.value: UInt64) := { value = self&._nanoseconds / 1000 }
milliseconds(.self: &Duration) -> (.value: UInt64) := { value = self&._nanoseconds / 1000000 }
seconds(.self: &Duration) -> (.value: UInt64) := { value = self&._nanoseconds / 1000000000 }

add(.left: Duration, .right: Duration) -> (.result: Errable#(.t: Duration,
        .reasons : (..out_of_range))) := {
    maximum: UInt64 = 18446744073709551615
    if left._nanoseconds > maximum - right._nanoseconds {
        result = ..error(.reason = ..out_of_range) return
    }
    result = ..ok Duration(.nanoseconds = left._nanoseconds + right._nanoseconds)
}
subtract(.left: Duration, .right: Duration) -> (.result: Errable#(.t: Duration,
        .reasons : (..out_of_range))) := {
    if left._nanoseconds < right._nanoseconds { result = ..error(.reason = ..out_of_range) return }
    result = ..ok Duration(.nanoseconds = left._nanoseconds - right._nanoseconds)
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
