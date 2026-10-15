dep := import("./dep")
app := import("./app")

-- This contract has the same short name as dep.Abstract, but a different
-- requirement. Its implementation must not affect app.consume_imported.
Abstract#(.Participant: Type): Contract = (
    .unrelated: (.value: Participant) -> (.result: Int32)
)

Widget : Type = ()

_impl_unrelated_Widget := (.value: Widget) -> (.result: Int32)  {
    result = 100
}

score(.value: Widget) -> (.result: Int32) := {
    result = 42
}

implement Abstract#(Widget) (.unrelated = _impl_unrelated_Widget)
implement dep.Abstract#(Widget) (.score = score)

main() -> (.status_code: Int32) := {
    status_code = app.consume_imported(.value = Widget()).result - 42
}
