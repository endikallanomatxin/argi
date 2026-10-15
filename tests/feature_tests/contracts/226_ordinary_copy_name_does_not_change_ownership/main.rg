Value: Type = (.value: Int32)

copy := (.self: &Value) -> (.result: Value) {
    result = (.value = self&.value)
}

main := () -> (.status_code: Int32 = 0) {
    original ::= Value(42)
    duplicated ::= original
    explicit ::= copy(&original)
    if duplicated.value != 42 or explicit.value != 42 { abort }
}
