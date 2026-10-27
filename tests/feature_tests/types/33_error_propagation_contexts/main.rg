step := () -> (.result: Errable#(.t: Void, .reasons: (..test_error))) { result = ..ok Void() }

value := () -> (.result: Errable#(.t: Int32, .reasons: (..test_error))) { result = ..ok 5 }

flag := () -> (.result: Errable#(.t: Bool, .reasons: (..test_error))) { result = ..ok true }

increment := (.x: Int32) -> (.value: Int32) { value = x + 1 }

statement := () -> (.result: Errable#(.t: Int32, .reasons: (..test_error))) {
    step()!
    result = ..ok 7
}

argument := () -> (.result: Errable#(.t: Int32, .reasons: (..test_error))) {
    out ::= increment(.x = value()!)
    result = ..ok out
}

condition := () -> (.result: Errable#(.t: Int32, .reasons: (..test_error))) {
    if flag()! { result = ..ok 1 } else { result = ..ok 2 }
}

assignment := () -> (.result: Errable#(.t: Int32, .reasons: (..test_error))) {
    x :: Int32 = 0
    x = value()!
    result = ..ok x
}

main := () -> (.status_code: Int32 = 0) {
    match statement() { ..ok payload { if payload != 7 { abort } } ..error _ { abort } }
    match argument() { ..ok payload { if payload != 6 { abort } } ..error _ { abort } }
    match condition() { ..ok payload { if payload != 1 { abort } } ..error _ { abort } }
    match assignment() { ..ok payload { if payload != 5 { abort } } ..error _ { abort } }
}
