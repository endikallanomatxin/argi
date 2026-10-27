..test_error

fail := () -> (.result: Errable#(.t: Int32, .reasons: (..test_error))) {
    result = ..error(.reason = ..test_error)
}

from_propagation := () -> !Int32 {
    value := fail()!
    result = ..ok value + 1
}

direct_error := () -> !Int32 {
    result = ..error(.reason = ..test_error)
}

explicit_output := () -> (.result: Errable#(.t: Int32)) {
    value := fail()!
    result = ..ok value + 2
}

main := () -> (.status_code: Int32 = 0) {
    match from_propagation() {
        ..ok _ { abort }
        ..error&err { match err&.reason { ..test_error {} } }
    }
    match direct_error() {
        ..ok _ { abort }
        ..error&err { match err&.reason { ..test_error {} } }
    }
    match explicit_output() {
        ..ok _ { abort }
        ..error&err { match err&.reason { ..test_error {} } }
    }
}
