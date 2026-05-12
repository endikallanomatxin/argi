..test_error

main () -> (.status_code: Int32) := {
    result : Errable#(.t: Int32, .reasons: (..test_error)) = ..error(.reason = ..test_error)

    match result {
        ..ok _ {
            status_code = 1
        }
        ..error & err {
            match err&.reason {
                ..test_error {
                    status_code = 0
                }
            }
        }
    }
}
