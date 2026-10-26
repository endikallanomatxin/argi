Error := <.reasons: Type> (.reason: reasons, .tracer: $&Virtual<.contract: ErrorTracer>)

Errable := <.t: Type, .reasons: Type> (
    ..ok t
    ..error Error<.reasons = reasons>
)

unwrap_or_abort := <.t: Type, .reasons: Type> (.value: Errable<t, reasons>) -> (.result: t) {
    match value {
        ..ok ~payload { result = ~payload }
        ..error _ { abort }
    }
}
