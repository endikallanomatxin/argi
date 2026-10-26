Token: Type = (.value: Int32)
TokenArgs := (.value: Int32)

once acquire := (.args: TokenArgs) -> (.result: Token) {
    result = (.value = args.value)
}

implement Init#(Token, TokenArgs) (
    .Result: Type = Token
    .init = acquire
)

main := () -> (.status_code: Int32 = 0) {
    token ::= Token(.value = 7)
    if token.value != 7 { abort }
}
