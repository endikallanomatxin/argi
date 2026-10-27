Token := (.value: Int32)

TokenArgs := (.value: Int32)

acquire := once TokenArgs -> (.result: Token) {
    result = (.value = value)
}

implement Init#(Token) (
    .init = acquire
)

main := () -> (.status_code: Int32 = 0) {
    token ::= Token(.value = 7)
    if token.value != 7 { abort }
}
