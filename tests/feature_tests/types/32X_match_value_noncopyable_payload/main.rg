Token : Type = (
    .value: Int32,
)

Token deinit(.self: $&Token) -> () := {
}

Result : Type = (
    ..ok(.token: Token),
    ..error,
)

main () -> (.status_code: Int32) := {
    value : Result = ..ok(.token = Token(.value = 7))

    match value {
        ..ok payload {
            status_code = payload.token.value
        }
        ..error {
            status_code = 1
        }
    }
}
