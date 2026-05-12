Result : Type = (
    ..ok(.value: Int32),
    ..error,
)

main () -> (.status_code: Int32) := {
    value :: Result = ..ok(.value = 3)

    match value {
        ..ok $& payload {
            payload&.value = 7
        }
        ..error {
            status_code = 1
            return
        }
    }

    match value {
        ..ok payload {
            status_code = payload.value - 7
        }
        ..error {
            status_code = 2
        }
    }
}
