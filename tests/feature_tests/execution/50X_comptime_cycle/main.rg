recursive() -> (.result: Int32 = 0) := {
    result = #run recursive()
}

main() -> (.status_code: Int32 = 0) := {
    status_code = #run recursive()
}
