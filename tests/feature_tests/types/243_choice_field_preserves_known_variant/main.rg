Result : Type = (
    ..ok Int32
    ..error Int32
)

Wrapper : Type = (.result: Result)

main() -> (.status_code: Int32 = 0) := {
    wrapper ::= Wrapper(.result = ..ok 42)
    payload ::= wrapper.result..ok
    status_code = payload - 42
}
