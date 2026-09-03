Result : Type = (
    ..ok Int32
    ..error Int32
)

main() -> (.status_code: Int32 = 0) := {
    value : Result = ..ok 42
    payload ::= value..ok
    status_code = payload - 42
}
