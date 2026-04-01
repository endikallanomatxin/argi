flag() -> (.result: Errable#(.t: Bool, .reasons: (..test_error))) := {
    result = ..ok(.value = true)
}

run() -> (.result: Errable#(.t: Int32, .reasons: (..test_error))) := {
    if flag()! {
        result = ..ok(.value = 1)
    } else {
        result = ..ok(.value = 2)
    }
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
