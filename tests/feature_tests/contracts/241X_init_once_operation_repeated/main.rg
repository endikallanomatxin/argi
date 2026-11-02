Token := (.value: Int32)

acquire := once (.value: Int32) -> (.result: Token) {
    result = (.value = value)
}

TokenInitArgs: Type = (.value: Int32)

implement Init#(Token, TokenInitArgs) (
    .Result : Type = Token

    .init = acquire
)

main := () -> () {
    first ::= Token(.value = 7)
    second ::= Token(.value = 8)
}
