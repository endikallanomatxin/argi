Widget := (.cleanups: $&Int32)

implement Deinit#(Widget) (
    .deinit = (.self: $&Widget) -> () {
        self&.cleanups&= self&.cleanups&+ 1
    }
)

implement Init#(Widget) (
    .init = (.cleanups: $&Int32) -> (.result: Errable#(.t: Widget, .reasons: (..rejected))) {
        _init_cleanups ::= ~cleanups

        constructed :: Widget = (.cleanups = _init_cleanups)
        result = ..error(.reason = ..rejected)
    }
)

main := () -> (.status_code: Int32 = 0) {
    cleanups :: Int32 = 0
    outcome ::= Widget(.cleanups = $&cleanups)
    match outcome {
        ..ok _ { status_code = 1 }
        ..error _ { if cleanups != 1 { status_code = 2 } }
    }
}
