produce() -> (.result: Errable#(.t: Void, .reasons: (..test_error))) := {
    result = ..ok(.value = Void())
}

main() -> (.status_code: Int32) := {
    result ::= produce()
    if is(.value = result, .variant = ..ok) {
    } else {
        status_code = 1
        return
    }

    status_code = 0
}
