native_read(.value: &Int32) -> (.result: Int32): CFunction(.symbol = "argi_access_read") where { reads(value) }
Token := (.value: Int32)
implement Deinit#(Token) (.deinit = (.self: $&Token) -> () {})
main := (.system: System) -> () {
    token ::= Token(.value = 7)
    reference ::= &token.value
    deinit(.self = $&token)
    _ = native_read(.value = reference, .ffi = system.ffi)
}
