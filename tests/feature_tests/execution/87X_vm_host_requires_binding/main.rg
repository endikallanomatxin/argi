main := () -> (.status_code: Int32 = 0) {
    assume ffi ::= $&ForeignFunctionInterface()
    putchar(.character = 65)
}
