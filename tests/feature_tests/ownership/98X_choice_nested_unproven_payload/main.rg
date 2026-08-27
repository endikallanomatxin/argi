Inner : Type = (
    ..a Int32
    ..b Int32
)

Outer : Type = (
    ..ok Inner
    ..error
)

main() -> (.status_code: Int32) := {
    inner_value :: Inner = ..a 7
    value :: Outer = ..ok inner_value
    if is(value, ..ok) {
        inner ::= value..ok
        payload ::= inner..a
        status_code = payload
    } else {
        status_code = 1
    }
}
