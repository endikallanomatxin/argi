Token: Type = ()
TokenArgs: Type = ()

once _acquire_token := (.args: TokenArgs) -> (.result: Token) {
    result = ()
}

implement Init#(Token, TokenArgs) (
    .Result : Type = Token
    .init   = _acquire_token
)

main := () -> (.status_code: Int32) {
    first := Token()
    second := Token()
    status_code = 0
}
