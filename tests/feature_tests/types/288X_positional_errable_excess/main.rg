Reasons: Type = (..unavailable)

check_fallible_result := () -> (.result: Errable<Void, Reasons, Int32>) {
    result = ..ok Void()
}

main := (.system: System) -> (.status_code: Int32 = 1) {
    assume writer ::= $&system.terminal&.stderr
    check_fallible_result()!!!
    status_code = 0
}
