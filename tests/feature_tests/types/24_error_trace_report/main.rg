fail() -> (.result: Errable#(.t: Int32, .reason: Char)) := {
    result = ..error(.reason = 'x')
}

middle() -> (.result: Errable#(.t: Int32, .reason: Char)) := {
    value := fail()!
    result = ..ok(.value = value)
}

top() -> (.result: Errable#(.t: Int32, .reason: Char)) := {
    value := middle() !! "reading config"
    result = ..ok(.value = value)
}

main(.system: System) -> (.status_code: Int32) := {
    result := top()

    if is(.value = result, .variant = ..error) {
        err := result..error
        report_trace(.trace = &err.trace)
        status_code = 0
    } else {
        status_code = 1
    }
}
