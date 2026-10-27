main := (.system: System) -> (.status_code: Int32 = 1) {
    assume writer ::= $&system.terminal&.stderr
    scalar ::= UnicodeScalar(.value = 65)!!!
    scalar._value = 55296
    status_code = 0
}
