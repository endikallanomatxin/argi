Reasons: Type = (..failed)

unwrap_or_abort := (.value: Errable#(Int32, Reasons)) -> (.result: Int32) { result = 0 }

main := () -> () {

    value: Errable#(Int32, Reasons) = ..ok 42
    _ ::= unwrap_or_abort(.value = ~value)
}
