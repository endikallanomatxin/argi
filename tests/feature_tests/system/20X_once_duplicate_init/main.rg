Token: Type = ()

TokenArgs: Type = ()

_acquire_token := once TokenArgs -> (.result: Token) {
    result = ()
}

TokenInitArgs: Type = TokenArgs

implement Init#(Token, TokenInitArgs) (
    .Result : Type = Token

    .init = _acquire_token
)

main := () -> (.status_code: Int32) {
    first := Token()
    second := Token()
    status_code = 0
}
