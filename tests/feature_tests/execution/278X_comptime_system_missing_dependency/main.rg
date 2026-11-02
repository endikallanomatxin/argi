answer ::= #run (.system: System) -> (.value: Int32) {
    print("not implicitly enabled")
    value = 42
}

main := () -> (.status_code: Int32) { status_code = answer }
