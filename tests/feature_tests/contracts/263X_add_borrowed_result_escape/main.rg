Left := (.value: Int32)

Right := (.value: Int32)

implement Add#(&Left, &Right) (
    .Result : Type = &Int32
    .add    = (.left: &Left, .right: &Right) -> (.result: Result) {
        result = &left&.value
    }
)

escape := () -> (.result: &Int32) {
    left ::= Left(7)
    right ::= Right(9)
    result = &left + &right
}

main := () -> () { value ::= escape() }
