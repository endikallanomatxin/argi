Widget := (.value: Int32)

implement Init#(Widget, ()) (
    .Result: Type = Int32
    .init = (.args: ()) -> (.value: Int32) {
        value = 1
    }
)

main := () -> (.status_code: Int32 = 0)  {
    widget ::= Widget()
    status_code = widget.value
}
