acquire := once () -> (.result: Int32) {
    result = 42
}

with_default := (.value: Int32 = acquire()) -> (.result: Int32) {
    result = value
}

main := () -> (.status_code: Int32 = 0) {
    explicit ::= with_default(.value = 7)
    if explicit != 7 { abort }
    status_code = with_default()
}
