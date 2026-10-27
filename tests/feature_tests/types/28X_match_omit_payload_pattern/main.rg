Result: Type = (
    ..ok(.value: Int32),
    ..error(.code: UnicodeScalar),
)

main := () -> (.status_code: Int32) {
    value: Result = ..error(.code = 'E')

    match value {
        ..ok payload {
            status_code = payload.value
        }
        ..error {
            status_code = 1
        }
    }
}
