Inner : Type = (
    ..a Int32
    ..b Int32
)

Outer : Type = (
    ..ok Inner
    ..error
)

choose(.condition: Bool) -> (.value: Inner) := {
    if condition {
        value = ..a 7
    } else {
        value = ..b 8
    }
}

main(.condition: Bool = true) -> (.status_code: Int32) := {
    inner_value ::= choose(.condition = condition)
    value :: Outer = ..ok inner_value
    if is(value, ..ok) {
        inner ::= value..ok
        payload ::= inner..a
        status_code = payload
    } else {
        status_code = 1
    }
}
