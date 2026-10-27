Widget := (.value: Int32)

WidgetInitArgs: Type = ()

implement Init#(Widget, WidgetInitArgs) (
    .Result : Type = Int32

    .init = WidgetInitArgs -> (.result: Result) {
        result = 1
    }
)

main := () -> (.status_code: Int32 = 0) {
    widget ::= Widget()
    status_code = widget.value
}
