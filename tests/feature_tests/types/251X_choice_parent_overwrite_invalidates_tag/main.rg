Result : Type = (
    ..ok Int32
    ..error Int32
)

Wrapper : Type = (
    .result: Result
    .counter: Int32
)

main() -> (.status_code: Int32 = 0) := {
    wrapper :: Wrapper = (
        .result = ..ok 42,
        .counter = 0,
    )
    wrapper = (
        .result = ..error 7,
        .counter = 1,
    )
    status_code = wrapper.result..ok
}
