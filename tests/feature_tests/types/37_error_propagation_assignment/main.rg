value() -> (.result: Errable#(.t: Int32, .reasons: (..test_error))) := {
    result = ..ok(.value = 5)
}

run() -> (.result: Errable#(.t: Int32, .reasons: (..test_error))) := {
    x :: Int32 = 0
    x = value()!
    result = ..ok(.value = x)
}

main() -> (.status_code: Int32) := {
    result ::= run()
    match result {
        ..ok payload {
            status_code = payload.value
        }
        ..error _ {
            status_code = 9
        }
    }
}
