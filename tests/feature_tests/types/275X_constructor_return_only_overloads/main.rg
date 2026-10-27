Box := #(.t: Type) (.tag: Int32)

Arguments := #(.sample: Type) (.value: sample)

implement#(.t: Type) Init#(Box#(.t: t)) (
    .init = #(.sample: Type) Arguments#(sample) -> (.result: Box#(.t: Int32)) {
        value ::= ~value

        _ ::= value
        result = (.tag = 1)
    }
)

implement#(.t: Type) Init#(Box#(.t: t)) (
    .init = #(.sample: Type) Arguments#(sample) -> (.result: Box#(.t: UnicodeScalar)) {
        value ::= ~value

        _ ::= value
        result = (.tag = 2)
    }
)

main := () -> (.status_code: Int32 = 0) {
    value ::= Box#(.t: Int32)(.value = 5)
    status_code = value.tag
}
