main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    storage ::= ForeignFunctionInterface()
    memory ::= Memory(.ffi = $&storage)
    moved ::= ~storage
    allocation ::= map_pages(.self = $&memory, .size = 4096, .alignment = 8)
}
