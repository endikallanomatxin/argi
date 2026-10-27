Payload := (
    .value : Int32,
)

implement Init#(Payload) (
    .init = (.value: Int32) -> (.result: Payload) {
        result = (.value = value)
    }
)

implement Deinit#(Payload) (
    .deinit = (.self: $&Payload) -> () {

    }
)

_ordinary_copy_0 := (.self: &Payload, .tag: Int32 = 1) -> (.value: Payload) {
    value = Payload(.value = self&.value)
}

_ordinary_copy_1 := (.self: &Payload, .flag: Bool = true) -> (.value: Payload) {
    value = Payload(.value = self&.value)
}

Result: Type = (
    ..ok Payload,
    ..error,
)

main := () -> (.status_code: Int32) {
    value: Result = ..ok Payload(.value = 7)
    payload := value ..ok
    status_code = payload.value - 7
}
