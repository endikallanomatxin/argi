Token := <.t: Type> (
    .tag: Int32
)

discard := (.value: Int32) -> ()  {
    _ ::= value
}

implement<.t: Type> Init<Token<.t: t>, (.sample: t)> (
    .Result: Type = Token<.t: t>
    .init = (.args: (.sample: t)) -> (.result: Result) {
        sample ::= ~args.sample

        defer discard(.value = 0)
        _ ::= sample
        result = (
            .tag = 1
        )
    }
)

main := () -> (.status_code: Int32)  {
    token ::= Token(.sample = 5)
    status_code = token.tag - 1
}
