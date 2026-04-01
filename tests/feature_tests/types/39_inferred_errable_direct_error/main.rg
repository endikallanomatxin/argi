..test_error

run() -> !Int32 := {
    result = ..error(.reason = ..test_error)
}

main() -> (.status_code: Int32) := {
    outcome := run()

    match outcome {
        ..ok payload {
            status_code = payload.value
            return
        }
        ..error & err {
            match err&.reason {
                ..test_error {
                    status_code = 42
                    return
                }
            }
        }
    }
}
