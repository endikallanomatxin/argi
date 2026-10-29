ArgumentSource#(.Source: Type): Contract = (
    .length : (.self: &Source) -> (.count: UIntNative) where {}
    .get    : (
        .self         : &Source,
        .index        : UIntNative,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(StringView, (..out_of_bounds, ..invalid_utf8))) where {
        on result ..ok { depends_on(result, self) }
        on result ..error { depends_on(result, error_tracer) }
    }
)
