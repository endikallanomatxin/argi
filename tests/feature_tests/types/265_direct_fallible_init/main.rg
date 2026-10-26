Widget := (.value: Int32)

implement Init<Widget, (.fail: Bool)> (
    .Result: Type = Errable<.t: Widget, .reasons: (..rejected)>
    .init = (.args: (.fail: Bool)) -> (.result: Result) {
        fail ::= ~args.fail

        constructed :: Widget

        if fail {
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
    match outcome {
        ..ok ~value { widget = ~value status_code = widget.value - 42 }
        ..error _ { status_code = 1 }
    }
}
