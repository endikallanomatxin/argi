Choice : Type = (
    ..a Int32
    ..b Int32
    ..c Int32
)

choose(.condition: Bool) -> (.value: Choice) := {
    if condition {
        value = ..b 7
    } else {
        value = ..c 8
    }
}

main(.condition: Bool = true) -> (.status_code: Int32) := {
    value ::= choose(.condition = condition)
    if is(value, ..a) {
        status_code = 1
    } else {
        payload ::= value..b
        status_code = payload
    }
}
