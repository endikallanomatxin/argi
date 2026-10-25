recursive() -> (.result: Int32 = 0) := {
    result = #run () -> (.value: Int32) { value = recursive() }
}

main() -> (.status_code: Int32 = 0) := {
    status_code = #run () -> (.value: Int32) { value = recursive() }
}
