Widget := (.value: Int32)

implement Init#(Widget) (
    .init = (.fail: Bool) -> (.result: Errable#(.t: Widget, .reasons: (..rejected))) {
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

main := () -> (.status_code: Int32)  {
    widget :: Widget
    outcome ::= Widget(.fail = false)
    status_code = widget.value
    match outcome {
        ..ok _ {}
        ..error _ {}
    }
}
