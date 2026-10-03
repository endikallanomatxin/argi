First : Type = (.value: Int32)
Second : Type = (.value: Int32)
First init() -> (.result: Second) := {
    result = (.value = 1)
}
main() -> (.status_code: Int32 = 0) := {
    value ::= First()
    status_code = value.value
}
