Source := (.reference: &Int32)

implement Convert#(Source, &Int32) (
    .Result  : Type = &Int32
    .convert = (.value: Source) -> (.result: Result) { result = value.reference }
)

make := () -> (.result: &Int32) {
    integer :: Int32 = 7
    result = Source(&integer) | convert#(.to: &Int32)(_)
}

main := () -> () { escaped ::= make() }
