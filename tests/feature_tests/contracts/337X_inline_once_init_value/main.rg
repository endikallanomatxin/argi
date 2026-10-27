Token: Type = ()

TokenInitArgs: Type = ()

implement Init#(Token, TokenInitArgs) (
    .Result : Type = Token

    .init = once TokenInitArgs -> (.result: Result) { result = () }
)

main := () -> () {
    first := Token()
    second := Token()
}
