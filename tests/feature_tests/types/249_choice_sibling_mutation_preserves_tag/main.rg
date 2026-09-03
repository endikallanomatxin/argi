Payload : Type = (.value: Int32)
Payload implements ImplicitlyCopyable

Result : Type = (
    ..ok Payload
    ..error Int32
)

Wrapper : Type = (
    .result: Result
    .counter: Int32
)

main() -> (.status_code: Int32 = 0) := {
    wrapper :: Wrapper = (
        .result = ..ok Payload(.value = 42),
        .counter = 0,
    )
    wrapper.counter = 1
    payload ::= wrapper.result..ok
    status_code = payload.value - 42
}
