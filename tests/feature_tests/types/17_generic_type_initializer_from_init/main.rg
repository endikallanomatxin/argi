Token := #(.t: Type) (
    .tag: Int32
)

implement#(.t: Type) Init#(Token#(.t: t), (.sample: t)) (
    .Result: Type = Token#(.t: t)
    .init = (.args: (.sample: t)) -> (.result: Result) {
        sample ::= ~args.sample

        _ ::= sample
        result = (
            .tag = 1
        )
    }
)

main := () -> (.status_code: Int32)  {
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
