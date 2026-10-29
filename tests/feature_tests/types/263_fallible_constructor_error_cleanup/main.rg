Widget := (.cleanups: $&Int32)

implement Deinit#(Widget) (
    .deinit = (.self: $&Widget) -> () {
        self&.cleanups&= self&.cleanups&+ 1
    }
)

WidgetInitArgs: Type = (
    .cleanups     : $&Int32,
    .error_tracer : $&Virtual#(ErrorTracer)
)

implement Init#(Widget, WidgetInitArgs) (
    .Result : Type = Errable#(.t: Widget, .reasons: (..rejected))

    .init = WidgetInitArgs -> (.result: Result) {
        assume error_tracer

        _init_cleanups ::= ~cleanups

        constructed :: Widget = (.cleanups = _init_cleanups)
        result = ..error(.reason = ..rejected)
    }
)

main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    cleanups :: Int32 = 0
    outcome ::= Widget(.cleanups = $&cleanups)
    match outcome {
        ..ok _ { status_code = 1 }
        ..error _ { if cleanups != 1 { status_code = 2 } }
    }
}
