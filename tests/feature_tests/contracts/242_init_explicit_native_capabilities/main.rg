main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    ffi ::= ForeignFunctionInterface()
    memory ::= Memory(.ffi = $&ffi)
    arguments ::= Arguments(.ffi = $&ffi)
    terminal ::= Terminal(.ffi = $&ffi)
}
