step() -> (.result: Errable#(.t: Void, .reasons: (..test_error))) := {
    result = ..ok Void()
}

run() -> (.result: Errable#(.t: Int32, .reasons: (..test_error))) := {
    step()!
    result = ..ok 7
}

main() -> (.status_code: Int32) := {
    result ::= run()
    match result {
        ..ok payload {
            status_code = payload
        }
        ..error _ {
            status_code = 1
        }
    }
}
