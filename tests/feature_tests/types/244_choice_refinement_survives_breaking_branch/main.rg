Result : Type = (
    ..ok Int32
    ..error Int32
)

make_result() -> (.result: Result) := {
    result = ..ok 42
}

main() -> (.status_code: Int32 = 1) := {
    while 1 == 1 {
        value ::= make_result()
        if value == ..error {
            break
        }
        payload ::= value..ok
        status_code = payload - 42
        break
    }
}
