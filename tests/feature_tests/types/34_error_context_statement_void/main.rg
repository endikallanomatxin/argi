fail() -> (.result: Errable#(.t: Void, .reasons: (..test_error))) := {
    result = ..error(.reason = ..test_error)
}

run() -> (.result: Errable#(.t: Int32, .reasons: (..test_error))) := {
    fail() !! "while stepping"
    result = ..ok(.value = 0)
}

main() -> (.status_code: Int32) := {
    result ::= run()
    match result {
        ..ok _ {
            status_code = 1
        }
        ..error & err {
            if err&.trace.entries.length != 1 {
                status_code = 2
                return
            }

            entry := err&.trace.entries[0]
            context_view ::= as_view(.self = entry.context)
            if equals(.left = &context_view, .right = "while stepping").ok {
                status_code = 0
            } else {
                status_code = 3
            }
        }
    }
}
