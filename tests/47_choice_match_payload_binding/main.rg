Result : Type = (
    ..ok(.value: Int32),
    ..error(.code: Char),
)

main () -> (.status_code: Int32) := {
    value : Result = ..ok(.value = 9)

    match value {
        ..ok(payload) {
            status_code = payload.value - 9
        }
        ..error(err) {
            status_code = 1
        }
    }
}
