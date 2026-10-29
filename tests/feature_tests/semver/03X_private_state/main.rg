semver := import ("semver")

main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    version ::= unwrap_or_abort(.value = semver.parse(.text = "1.2.3")).result
    value ::= version._text
}
