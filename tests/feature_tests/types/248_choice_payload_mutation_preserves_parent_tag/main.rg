Payload : Type = (
    .value: Int32
)

Payload implements ImplicitlyCopyable

Result : Type = (
    ..ok Payload
    ..error Int32
)

main() -> (.status_code: Int32 = 0) := {
    result :: Result = ..ok Payload(.value = 1)
    result..ok.value = 42

    payload ::= result..ok
    status_code = payload.value - 42
}
