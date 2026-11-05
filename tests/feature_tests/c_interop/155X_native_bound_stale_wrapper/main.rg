native_read(.value: &Int32) -> (.result: Int32): CFunction(.symbol = "argi_access_read") where { reads(value) }
Token := (.value: Int32)
implement Deinit#(Token) (.deinit = (.self: $&Token) -> () {})
read_wrapper := (.value: &Int32, .ffi: $&ForeignFunctionInterface) -> (.result: Int32) { result = native_read(.value = value, .ffi = ffi) }
main := (.system: System) -> () {
    token ::= Token(.value = 7)
    reference ::= &token.value
    deinit(.self = $&token)
    _ = read_wrapper(.value = reference, .ffi = system.ffi)
}
