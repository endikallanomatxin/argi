Payload : Type = (
    .value: Int32,
)

init(.payload: $&Payload) -> () := {}

deinit(.payload: $&Payload) -> () := {}


copy(.self: &Payload, .tag: Int32 = 1) -> (.value: Payload) := {
    value = Payload(.value = self&.value)
}

copy(.self: &Payload, .flag: Bool = true) -> (.value: Payload) := {
    value = Payload(.value = self&.value)
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
