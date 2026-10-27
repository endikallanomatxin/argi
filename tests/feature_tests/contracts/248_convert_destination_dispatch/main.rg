Source := (.value: Int32)

Small := (.value: Int32)

Large := (.value: Int32)

implement Convert#(Source, Small) (
    .Result  : Type = Small
    .convert = (.value: Source) -> (.result: Result) {
        result = (.value = value.value + 1)
    }
)

implement Convert#(Source, Large) (
    .Result  : Type = Large
    .convert = (.value: Source) -> (.result: Result) {
        result = (.value = value.value + 10)
    }
)

change := #(.From: Type, .To: Type) (.value: From) -> (.result: Convert#(From, To).Result) {
    result = ~[~value | convert#(.to: To)(_)]
}

main := () -> (.status_code: Int32 = 0) {
    source ::= Source(7)
    small ::= source | convert#(.to: Small)(_)
    large ::= source | convert#(.to: Large)(_)
    generic ::= change#(.To: Large)(source)
    qualified ::= Convert#(Source, Small).convert(source)
    if small.value != 8 or large.value != 17 or generic.value != 17 or qualified.value != 8 {
        status_code = 1
    }
}
