Widget := (.value: Int32)

implement Init#(Widget, ()) (
    .Result: Type = Errable#(.t: Widget, .reasons: (..rejected))
    .init = (.args: ()) -> (.result: Result) {
        constructed :: Widget

        result = ..error(.reason = ..rejected)
    }
)

main := () -> (.status_code: Int32)  {
    widget :: Widget
    outcome ::= Widget()
    match outcome {
        ..ok _ { status_code = 0 }
        ..error _ { status_code = widget.value }
    }
}
