Token: Type = (.value: Int32)

once acquire := (.args: (.value: Int32)) -> (.result: Token) {
    result = (.value = args.value)
}

implement Init#(Token, (.value: Int32)) (
    .Result: Type = Token
    .init = acquire
)

main := () -> () {
    first ::= Token(.value = 7)
    second ::= Token(.value = 8)
}
