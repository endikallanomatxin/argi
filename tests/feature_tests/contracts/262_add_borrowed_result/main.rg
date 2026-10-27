Left := (.value: Int32)

Right := (.value: Int32)

implement Add#(&Left, &Right) (
    .Result : Type = &Int32
    .add    = (.left: &Left, .right: &Right) -> (.result: Result) {
        result = &left&.value
    }
)

main := () -> (.status_code: Int32 = 0) {
    left ::= Left(7)
    right ::= Right(9)
    value ::= &left + &right
    if value&!= 7 { status_code = 1 }
}
