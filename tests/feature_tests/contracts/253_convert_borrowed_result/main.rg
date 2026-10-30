Source := (.reference: &Int32)

implement Convert#(Source, &Int32) (
    .Result  : Type = &Int32
    .convert = (.value: Source) -> (.result: Result) {
        result = value.reference
    }
)

main := () -> (.status_code: Int32 = 0) {

    integer :: Int32 = 7
    source ::= Source(&integer)
    borrowed ::= source | convert#(.to: &Int32)(_)
    if borrowed&!= 7 { status_code = 1 }
}
