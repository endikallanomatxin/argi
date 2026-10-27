Box := #(.t: Type) (.tag: Int32)

Arguments := #(.sample: Type) (.value: sample)

BoxInitArgs: Type = #(.t: Type, .sample: Type) Arguments#(sample)

implement#(.t: Type, .sample: Type) Init#(Box#(.t: t), BoxInitArgs#(t, sample)) (
    .Result : Type = Box#(.t: Int32)

    .init = BoxInitArgs#(t, sample) -> (.result: Result) {
        value ::= ~value

        _ ::= value
        result = (.tag = 1)
    }
)

implement#(.t: Type, .sample: Type) Init#(Box#(.t: t), BoxInitArgs#(t, sample)) (
    .Result : Type = Box#(.t: UnicodeScalar)

    .init = BoxInitArgs#(t, sample) -> (.result: Result) {
        value ::= ~value

        _ ::= value
        result = (.tag = 2)
    }
)

main := () -> (.status_code: Int32 = 0) {
    value ::= Box#(.t: Int32)(.value = 5)
    status_code = value.tag
}
