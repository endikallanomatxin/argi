Payload := (
    .value : Int32,
)

implement Init#(Payload, (.value: Int32)) (
    .Result : Type = Payload
    .init   = (.args: (.value: Int32)) -> (.result: Result) {
        value ::= ~args.value

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
    result: Result = ..ok Payload(.value = 7)

    match result {
        ..ok payload {
            status_code = payload.value - 7
        }
        ..error {
            status_code = 1
        }
    }
}
