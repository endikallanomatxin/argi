Token := #(.t: Type) (
    .tag : Int32
)

TokenInitArgs: Type = #(.t: Type) (.sample: t)

implement#(.t: Type) Init#(Token#(.t: t), TokenInitArgs#(t)) (
    .Result : Type = Token#(.t: t)

    .init = TokenInitArgs#(t) -> (.result: Result) {
        _init_sample ::= ~sample

        _ ::= _init_sample
        result = (.tag = 1)
    }
)

main := () -> (.status_code: Int32) {
    int_token ::= Token(.sample = 5)
    char_token ::= Token(.sample = 'a')

    if int_token.tag != 1 {
        status_code = 1
        return
    }

    if char_token.tag != 1 {
        status_code = 2
        return
    }

    status_code = 0
}
