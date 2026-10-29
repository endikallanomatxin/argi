Value := (.number: Int32)

Small := (.amount: Int32)

Large := (.amount: Int32)

implement Add#(&Value, &Value) (
    .Result : Type = Int32
    .add    = #(.Provider: Type) (.left: &Value, .right: &Value, .provider: &Provider) -> (
        .result : Result
    ) {
        result = left&.number + right&.number + provider&.amount
    }
)

with_provider := #(.Provider: Type) (.provider: &Provider) -> (.result: Int32) {
    assume provider
    left ::= Value(1)
    right ::= Value(2)
    result = &left + &right
}

known ::= #run () -> (.result: Int32) {
    provider ::= Small(4)
    result = with_provider(&provider)
}

main := () -> (.status_code: Int32 = 0) {
    small ::= Small(4)
    large ::= Large(8)
    if with_provider(&small) != 7 or with_provider(&large) != 11 { status_code = 1 }
    left ::= Value(1)
    right ::= Value(2)
    explicit ::= Add#(&Value, &Value).add(.left = &left, .right = &right, .provider = &small)
    if explicit != 7 or known != 7 { status_code = 2 }
}
