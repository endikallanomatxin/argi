Payload : Type = (
    .value: Int32,
)

implement Init#(Payload, (.value: Int32)) (
    .Result: Type = Payload
    .init = (.args: (.value: Int32)) -> (.result: Result) {
        result = (.value = args.value)
    }
)

implement Deinit#(Payload) (
    .deinit = (.self: $&Payload) -> () {

    }
)


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
