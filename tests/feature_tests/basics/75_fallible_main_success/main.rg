work := () -> !Void = ..ok Void() {

}

main := (.system: System) -> (.status_code: Int32 = 1) {

    assume writer ::= $&system.terminal&.stderr
    work()!!!
    status_code = 0
}
