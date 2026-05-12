flag() -> (.result: Errable#(.t: Bool, .reasons: (..test_error))) := {
    result = ..ok true
}

run() -> (.result: Errable#(.t: Int32, .reasons: (..test_error))) := {
    if flag()! {
        result = ..ok 1
    } else {
        result = ..ok 2
    }
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
