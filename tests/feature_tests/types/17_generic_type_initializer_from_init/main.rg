Token := #(.t: Type) (
    .tag : Int32
)

implement#(.t: Type) Init#(Token#(.t: t)) (
    .init = (.sample: t) -> (.result: Token#(.t: t)) {
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
