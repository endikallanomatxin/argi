Widget := (.value: Int32)

WidgetInitArgs: Type = (
    .error_tracer : $&Virtual#(ErrorTracer)
)

implement Init#(Widget, WidgetInitArgs) (
    .Result : Type = Errable#(.t: Widget, .reasons: (..rejected))

    .init = WidgetInitArgs -> (.result: Result) {
        assume error_tracer

        constructed :: Widget

        result = ..error(.reason = ..rejected)
    }
)

main := () -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    widget :: Widget
    outcome ::= Widget()
    match outcome {
        ..ok _ { status_code = 0 }
        ..error _ { status_code = widget.value }
    }
}
