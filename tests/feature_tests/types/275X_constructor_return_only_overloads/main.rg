Box := #(.t: Type) (.tag: Int32)

Arguments := #(.sample: Type) (.value: sample)

implement#(.sample: Type, .t: Type) Init#(Box#(.t: t), Arguments#(sample)) (
    .Result : Type = Box#(.t: Int32)
    .init   = (.args: Arguments#(sample)) -> (.result: Result) {
        value ::= ~args.value

        _ ::= value
        result = (.tag = 1)
    }
)

implement#(.sample: Type, .t: Type) Init#(Box#(.t: t), Arguments#(sample)) (
    .Result : Type = Box#(.t: UnicodeScalar)
    .init   = (.args: Arguments#(sample)) -> (.result: Result) {
        value ::= ~args.value

        _ ::= value
        result = (.tag = 2)
    }
)

main := () -> (.status_code: Int32 = 0) {
    value ::= Box#(.t: Int32)(.value = 5)
    status_code = value.tag
}
