Token: Type = ()

implement Init#(Token) (
    .init = once () -> (.result: Token) { result = () }
)

main := () -> () {
    first := Token()
    second := Token()
}
