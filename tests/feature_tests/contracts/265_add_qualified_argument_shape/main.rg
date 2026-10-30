Left := (.value: Int32)

Right := (.value: Int32)

implement Add#(&Left, &Right) (
    .Result : Type = Int32
    .add    = (.left: &Left, .right: &Right, .bias: Int32 = 1) -> (.result: Result) {
        result = left&.value + right&.value + bias
    }
)

main := () -> (.status_code: Int32 = 0) {

    left ::= Left(1)
    right ::= Right(2)
    value ::= Add#(&Left, &Right).add(.left = &left, .right = &right, .bias = 5)
    if value != 8 { status_code = 1 }
}
