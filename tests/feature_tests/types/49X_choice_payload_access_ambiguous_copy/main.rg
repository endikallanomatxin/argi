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
    value : Result = ..ok Payload(.value = 7)
    payload := value..ok
    status_code = payload.value - 7
}
