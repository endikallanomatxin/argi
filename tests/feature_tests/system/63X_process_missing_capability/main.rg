main := () -> () {
    assume error_tracer ::= $&noop_error_tracer
    spawn(.executable = "test")
}
