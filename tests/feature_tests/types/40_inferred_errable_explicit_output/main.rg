..test_error

fail() -> (.result: Errable#(.t: Int32, .reasons: (..test_error))) := {
    result = ..error(.reason = ..test_error)
}

run() -> (.result: Errable#(.t: Int32)) := {
    value := fail()!
    result = ..ok value + 2
}

main() -> (.status_code: Int32) := {
    outcome := run()

    match outcome {
        ..ok payload {
            status_code = payload
            return
        }
        ..error & err {
            match err&.reason {
                ..test_error {
                    status_code = 40
                    return
                }
            }
        }
    }
}
