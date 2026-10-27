Box := #(.T: Type) (.value: T, .small: Int8)

implement#(.T: Type) Init#(Box#(T)) (
    .init = (.value: T, .small: Int8 = 128) -> (.result: Box#(T)) {
        result = (.value = value, .small = small)
    }
)

main := () -> () { value ::= Box#(Int32)(.value = 42) }
