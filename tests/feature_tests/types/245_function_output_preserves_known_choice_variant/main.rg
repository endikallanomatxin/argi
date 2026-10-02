Result : Type = (
    ..ok Int32
    ..error Int32
)

make_result() -> (.result: Result) := {
    result = ..ok 42
}

main() -> (.status_code: Int32 = 0) := {
    value ::= make_result()
    payload ::= value..ok
    status_code = payload - 42
}
