Result : Type = (
    ..ok Int32
    ..pending Int32
    ..error Int32
)

make_result() -> (.result: Result) := {
    result = ..pending 7
}

main() -> (.status_code: Int32 = 0) := {
    value ::= make_result()
    if value != ..error {
        payload ::= value..ok
        status_code = payload
    }
}
