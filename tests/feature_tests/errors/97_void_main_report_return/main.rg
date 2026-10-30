..missing

attempt := () -> (.result: Errable#(Void, (..missing))) {

    result = ..error(.reason = ..missing)
}

main := (.system: System) -> () {

    assume writer ::= $&system.terminal&.stderr
    attempt()!!!
    abort
}
