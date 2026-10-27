Token := (.value: Int32)

acquire := once (.value: Int32) -> (.result: Token) {
    result = (.value = value)
}

implement Init#(Token) (
    .init = acquire
)

main := () -> () {
    first ::= Token(.value = 7)
    second ::= Token(.value = 8)
}
