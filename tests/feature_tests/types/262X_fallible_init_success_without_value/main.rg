Widget := (.value: Int32)

WidgetInitArgs: Type = (
    .error_tracer : $&Virtual#(ErrorTracer)
)

implement Init#(Widget, WidgetInitArgs) (
    .Result : Type = Errable#(.t: Widget, .reasons: (..rejected))

    .init = WidgetInitArgs -> (.result: Result) {
        assume error_tracer

        constructed :: Widget

        result = ..ok ~constructed
    }
)

main := () -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    constructed ::= Widget()
    match constructed {
        ..ok value { status_code = value.value }
        ..error _ { status_code = 1 }
    }
}
