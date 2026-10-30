Widget := (.value: Int32)

WidgetInitArgs: Type = (
)

implement Init#(Widget, WidgetInitArgs) (
    .Result : Type = Errable#(.t: Widget, .reasons: (..rejected))

    .init = WidgetInitArgs -> (.result: Result) {

        constructed :: Widget

        result = ..ok ~constructed
    }
)

main := () -> (.status_code: Int32) {

    constructed ::= Widget()
    match constructed {
        ..ok value { status_code = value.value }
        ..error _ { status_code = 1 }
    }
}
