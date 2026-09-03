establish_fresh_reference(.value: Int32) -> (.result: Int32) := {
    result = value
}

main() -> (.status_code: Int32) := {
    status_code = establish_fresh_reference(.value = 0)
}
