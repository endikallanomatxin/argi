Result : Type = (
    ..ok Int32
    ..error Int32
)

main(.condition: Bool = true) -> (.status_code: Int32 = 0) := {
    value :: Result = ..error 0
    if condition {
        value = ..ok 40
    } else {
        value = ..ok 42
    }
    payload ::= value..ok
    status_code = payload - 40
}
