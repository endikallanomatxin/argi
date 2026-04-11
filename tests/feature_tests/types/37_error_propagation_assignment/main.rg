value() -> (.result: Errable#(.t: Int32, .reasons: (..test_error))) := {
    result = ..ok 5
}

run() -> (.result: Errable#(.t: Int32, .reasons: (..test_error))) := {
    x :: Int32 = 0
    x = value()!
    result = ..ok x
}

main() -> (.status_code: Int32) := {
    result ::= run()
    match result {
        ..ok payload {
            status_code = payload
        }
        ..error _ {
            status_code = 9
        }
    }
}
