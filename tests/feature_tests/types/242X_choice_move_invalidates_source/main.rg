Result : Type = (
    ..ok Int32
    ..error Int32
)

main() -> (.status_code: Int32 = 0) := {
    source : Result = ..ok 42
    _ ::= ~source
    payload ::= source..ok
    status_code = payload
}
