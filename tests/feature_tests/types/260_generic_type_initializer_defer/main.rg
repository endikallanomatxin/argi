Token := #(.t: Type) (
    .tag : Int32
)

discard := (.value: Int32) -> () {
    _ ::= value
}

TokenInitArgs: Type = #(.t: Type) (.sample: t)

implement#(.t: Type) Init#(Token#(.t: t), TokenInitArgs#(t)) (
    .Result : Type = Token#(.t: t)

    .init = TokenInitArgs#(t) -> (.result: Result) {
        _init_sample ::= ~sample

        defer discard(.value = 0)
        _ ::= _init_sample
        result = (.tag = 1)
    }
)

main := () -> (.status_code: Int32) {
    token ::= Token(.sample = 5)
    status_code = token.tag - 1
}
