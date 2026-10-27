Value := (.number: Int32)

Bias := (.amount: Int32)

implement Add#(&Value, &Value) (
    .Result : Type = Int32
    .add    = #(.Provider: Type) (
        .left: &Value, .right: &Value, .provider: &Provider = reach provider
    ) -> (.result: Result) {
        result = left&.number + right&.number + provider&.amount
    }
)

main := () -> (.status_code: Int32 = 0) {
    bias ::= Bias(4)
    assume provider := &bias
    left ::= Value(1)
    right ::= Value(2)
    if add(.left = &left, .right = &right) != 7 { status_code = 1 }
    if add#(.Provider: Bias)(.left = &left, .right = &right) != 7 { status_code = 2 }
}
