Token := #(.t: Type) (
    .tag : Int32
)

discard := (.value: Int32) -> () {
    _ ::= value
}

implement#(.t: Type) Init#(Token#(.t: t)) (
    .init = (.sample: t) -> (.result: Token#(.t: t)) {
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
