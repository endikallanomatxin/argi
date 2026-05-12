identity(.value: Int32) -> (.result) := {
    result = value
}

main() -> (.status_code: Int32) := {
    status_code = identity(.value = 1)
}
