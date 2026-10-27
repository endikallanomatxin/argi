Token := (
    .value : Int32,
)

implement Deinit#(Token) (
    .deinit = (.self: $&Token) -> () {

    }
)

Result: Type = (
    ..ok(.token: Token),
    ..error,
)

main := () -> (.status_code: Int32) {
    value: Result = ..ok(.token = Token(.value = 7))

    match value {
        ..ok payload {
            status_code = payload.token.value
        }
        ..error {
            status_code = 1
        }
    }
}
