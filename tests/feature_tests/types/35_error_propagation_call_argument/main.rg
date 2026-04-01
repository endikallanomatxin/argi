value() -> (.result: Errable#(.t: Int32, .reasons: (..test_error))) := {
    result = ..ok(.value = 5)
}

increment(.x: Int32) -> (.value: Int32) := {
    value = x + 1
}

run() -> (.result: Errable#(.t: Int32, .reasons: (..test_error))) := {
    out ::= increment(.x = value()!)
    result = ..ok(.value = out)
}

main() -> (.status_code: Int32) := {
    result ::= run()
    match result {
        ..ok payload {
            status_code = payload.value
        }
        ..error _ {
            status_code = 1
        }
    }
}
