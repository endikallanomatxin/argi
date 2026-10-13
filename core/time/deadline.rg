Deadline: Type = (._instant: MonotonicInstant)

implement ImplicitlyCopyable#(Deadline) ()

implement Init#(Deadline, (.at: MonotonicInstant)) (
    .Result: Type = Deadline
    .init = (.args: (.at: MonotonicInstant)) -> (.result: Result) {
        at ::= args.at

        result = (._instant = at)
    }
)

deadline_after(
        .after : Duration,
        .now   : MonotonicInstant
    ) -> (
        .result : Errable#(Deadline, (..out_of_range))
    ) := {
    instant ::= checked_add(.left = now._nanoseconds, .right = after._nanoseconds)!

    result = ..ok(._instant = (._nanoseconds = instant))
}

expired(.self: Deadline, .now: MonotonicInstant) -> (.value: Bool) := {
    value = compare(.left = now, .right = self._instant).order >= 0
}

-- Remaining time saturates at zero. Deadlines never depend on wall-clock time.
remaining(.self: Deadline, .now: MonotonicInstant) -> (.value: Duration) := {
    if expired(self, .now = now).value {
        value = Duration(.nanoseconds = 0)
        return
    }

    value = Duration(.nanoseconds = self._instant._nanoseconds - now._nanoseconds)
}
