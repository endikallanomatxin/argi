Left := (.value: Int32)

Right := (.value: Int32)

implement Add#(&Left, &Right) (
    .Result : Type = Int32
    .add    = (.left: &Left, .right: &Right, .bias: Int32 = 1) -> (.result: Result) {
        result = left&.value + right&.value + bias
    }
)

implement Add#(&Left, &Right) (
    .Result : Type = Int32
    .add    = (.left: &Left, .right: &Right, .offset: Int32 = 2) -> (.result: Result) {
        result = left&.value + right&.value + offset
    }
)

main := () -> () {
    left ::= Left(1)
    right ::= Right(2)
    value ::= &left + &right
}
