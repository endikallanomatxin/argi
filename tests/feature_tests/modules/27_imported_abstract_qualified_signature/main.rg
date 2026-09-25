dep := #import("./dep")
app := #import("./app")

-- This contract has the same short name as dep.Abstract, but a different
-- requirement. Its implementation must not affect app.consume_imported.
Abstract : Abstract = (
    unrelated(.value: Self) -> (.result: Int32)
)

Widget : Type = ()

unrelated(.value: Widget) -> (.result: Int32) := {
    result = 100
}

score(.value: Widget) -> (.result: Int32) := {
    result = 42
}

Widget implements Abstract
Widget implements dep.Abstract

main() -> (.status_code: Int32) := {
    status_code = app.consume_imported(.value = Widget()).result - 42
}
