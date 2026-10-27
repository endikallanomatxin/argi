Payload := (.value: Int32)
implement ImplicitlyCopyable#(Payload) ()

Result : Type = (
    ..ok Payload
    ..error Int32
)

Wrapper := (
    .result: Result
    .counter: Int32
)

main := () -> (.status_code: Int32 = 0)  {
    wrapper :: Wrapper = (
        .result = ..ok Payload(.value = 42),
        .counter = 0,
    )
    wrapper.counter = 1
    payload ::= wrapper.result..ok
    status_code = payload.value - 42
}
