main := (.system: System) -> (.status_code: Int32 = 0) {

    assume ffi := system.ffi
    assume writer ::= $&system.terminal&.stdout

    text ::= "borrowed view"
    print(.value = text)
}
