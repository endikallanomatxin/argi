main := (.system: System) -> (.status_code: Int32 = 0) {

    assume ffi := system.ffi
    assume writer ::= $&system.terminal&.stderr

    text ::= "borrowed err"
    print_error(.value = text)
}
