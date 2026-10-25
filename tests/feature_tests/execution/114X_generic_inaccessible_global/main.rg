foreign := import ("./foreign")

read#(.T: Type) := (.input: T) -> (.result: Int32) {
    result = foreign_value
}

main := () -> (.status_code: Int32) {
    status_code = read(.input = true)
}
