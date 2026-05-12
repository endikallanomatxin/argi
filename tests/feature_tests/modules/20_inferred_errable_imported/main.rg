main () -> (.status_code: Int32) := {
    dep := #import("./dep")
    outcome := dep.load()

    match outcome {
        ..ok payload {
            status_code = payload
            return
        }
        ..error & err {
            match err&.reason {
                ..import_error {
                    status_code = 43
                    return
                }
            }
        }
    }
}
