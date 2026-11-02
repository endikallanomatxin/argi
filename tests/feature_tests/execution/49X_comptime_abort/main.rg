fail := () -> (.result: Int32 = 0) { abort }

main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    status_code = #run () -> (.value: Int32) { value = fail() }
}
