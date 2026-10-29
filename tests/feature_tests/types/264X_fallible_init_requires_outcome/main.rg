Widget := (.value: Int32)

WidgetInitArgs: Type = (
    .fail         : Bool,
    .error_tracer : $&Virtual#(ErrorTracer)
)

implement Init#(Widget, WidgetInitArgs) (
    .Result : Type = Errable#(.t: Widget, .reasons: (..rejected))

    .init = WidgetInitArgs -> (.result: Result) {
        assume error_tracer

        _init_fail ::= ~fail

        constructed :: Widget

        if _init_fail {
            result = ..error(.reason = ..rejected)
            return
        }
        constructed = (.value = 42)
        result = ..ok ~constructed
    }
)

main := () -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    widget :: Widget
    outcome ::= Widget(.fail = false)
    status_code = widget.value
    match outcome {
        ..ok _ {}
        ..error _ {}
    }
}
