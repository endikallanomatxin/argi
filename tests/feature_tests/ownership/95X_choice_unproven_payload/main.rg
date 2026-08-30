Choice : Type = (
    ..a Int32
    ..b Int32
)

choose(.condition: Bool) -> (.value: Choice) := {
    if condition {
        value = ..a 7
    } else {
        value = ..b 8
    }
}

main(.condition: Bool = true) -> (.status_code: Int32) := {
    value ::= choose(.condition = condition)
    payload ::= value..a
    status_code = payload
}
