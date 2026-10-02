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
        if inner == ..a {
            payload ::= inner..a
            status_code = payload - 7
        } else {
            status_code = 1
        }
    } else {
        status_code = 2
    }
}
