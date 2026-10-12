main := () -> () {
    tracer ::= NoopErrorTracer()
    reset_context($&tracer)
}
