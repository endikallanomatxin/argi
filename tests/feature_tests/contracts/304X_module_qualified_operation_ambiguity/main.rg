operations := import("./operations")
main := (.system: System) -> (.status_code: Int32 = 0) {
    value ::= operations.query(.value = 1)
}
