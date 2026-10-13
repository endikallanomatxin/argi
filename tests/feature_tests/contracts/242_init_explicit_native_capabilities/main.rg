main := () -> (.status_code: Int32 = 0) {
    ffi ::= ForeignFunctionInterface()
    memory ::= Memory(.ffi = $&ffi)
    arguments ::= Arguments(.ffi = $&ffi)
    terminal ::= Terminal(.ffi = $&ffi)
}
