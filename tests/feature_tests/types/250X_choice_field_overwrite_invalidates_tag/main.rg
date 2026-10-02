Result : Type = (
    ..ok Int32
    ..error Int32
)

Wrapper : Type = (.result: Result)

main() -> (.status_code: Int32 = 0) := {
    wrapper :: Wrapper = (.result = ..ok 42)
    wrapper.result = ..error 7
    status_code = wrapper.result..ok
}
