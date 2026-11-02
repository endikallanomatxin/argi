main := () -> (.status_code: Int32) {
    assume ffi ::= $&ForeignFunctionInterface()
    address ::= aligned_alloc(.alignment = 8, .size = 16).address
    if address == 0 { abort }
    if address % 8 != 0 { abort }
    aligned_free(.address = address)
    free(.address = 0)
    status_code = 42
}
