Result : Type = (
    ..ok Int32
    ..error Int32
)

main(.condition: Bool = true) -> (.status_code: Int32 = 0) := {
    value :: Result = ..ok 0
    if condition {
        value = ..ok 42
    } else {
        value = ..error 7
    }
    payload ::= value..ok
    status_code = payload
}
