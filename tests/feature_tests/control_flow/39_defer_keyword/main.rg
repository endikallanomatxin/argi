Flag#(.T: Type): Contract = ()

Marker: Type = ()

implement Flag#(Marker) ()

implement#(.T: Type: Flag) Flag#(&T) ()

append := (.state: $&Int32, .digit: Int32) -> () {
    state&= state&* 10 + digit
}

finish := (.state: $&Int32) -> () {

    defer append(.state = state, .digit = 1)
    defer { state&= state&* 10 + 2 }
}

main := () -> (.status_code: Int32 = 0) {

    state :: Int32 = 0
    finish($&state)
    if state != 21 { status_code = 1 }
}
