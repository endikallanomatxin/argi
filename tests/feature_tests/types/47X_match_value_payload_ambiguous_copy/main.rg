Payload : Type = (
    .value: Int32,
)

init(.payload: $&Payload) -> () := {}

deinit(.payload: $&Payload) -> () := {}

copy(.payload: Payload, .tag: Int32 = 1) -> (.out: Payload) := {
    out = Payload(.value = payload.value)
}

copy(.payload: Payload, .flag: Bool = true) -> (.out: Payload) := {
    out = Payload(.value = payload.value)
}

Result : Type = (
    ..ok Payload,
    ..error,
)

main () -> (.status_code: Int32) := {
    result : Result = ..ok Payload(.value = 7)

    match result {
        ..ok payload {
            status_code = payload.value - 7
        }
        ..error {
            status_code = 1
        }
    }
}
