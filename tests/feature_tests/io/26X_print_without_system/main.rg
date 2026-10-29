main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    print("Hello, World!\n")
}
