Flag#(.T: Type): Contract = ()

Marker: Type = ()

implement Flag#(Marker) ()

implement#(.T: Type: Flag) Flag#(&T) ()

append := (.state: $&Int32, .digit: Int32) -> () {
    state&= state&* 10 + digit
}

finish := (.state: $&Int32, .error_tracer: $&Virtual#(ErrorTracer)) -> () {
    assume error_tracer
    defer append(.state = state, .digit = 1)
    defer { state&= state&* 10 + 2 }
}

main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    state :: Int32 = 0
    finish($&state)
    if state != 21 { status_code = 1 }
}
