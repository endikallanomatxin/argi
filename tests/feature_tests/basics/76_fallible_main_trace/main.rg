..startup_failed

fail := () -> !Void {
    result = ..error(.reason = ..startup_failed)
    add_context(.context = "starting application")
}

main := (.system: System) -> (.status_code: Int32 = 1) {
    assume writer ::= $&system.terminal&.stderr
    fail()!!!
    status_code = 0
}
