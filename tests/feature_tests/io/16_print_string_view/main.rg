main := (.system: System) -> (.status_code: Int32 = 0) {
    assume ffi := system.ffi
    assume writer ::= $&system.terminal&.stdout

    text ::= "string view output"
    print(.value = text)
}
