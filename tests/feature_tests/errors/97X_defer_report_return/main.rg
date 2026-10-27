fail := () -> !Void = ..ok Void() {}

main := (.system: System) -> () {
    assume writer ::= $&system.terminal&.stderr
    defer { fail()!!! }
}
