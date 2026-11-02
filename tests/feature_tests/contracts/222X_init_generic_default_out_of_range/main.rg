Box := #(.T: Type) (.value: T, .small: Int8)

BoxInitArgs: Type = #(.T: Type) (.value: T, .small: Int8 = 128)

implement#(.T: Type) Init#(Box#(T), BoxInitArgs#(T)) (
    .Result : Type = Box#(T)

    .init = BoxInitArgs#(T) -> (.result: Result) {
        result = (.value = value, .small = small)
    }
)

main := () -> () { value ::= Box#(Int32)(.value = 42) }
