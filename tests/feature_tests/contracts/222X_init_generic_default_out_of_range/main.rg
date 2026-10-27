Box := #(.T: Type) (.value: T, .small: Int8)

implement#(.T: Type) Init#(Box#(T), (.value: T, .small: Int8 = 128)) (
    .Result : Type = Box#(T)
    .init   = (.args: (.value: T, .small: Int8 = 128)) -> (.result: Result) {
        result = (.value = args.value, .small = args.small)
    }
)

main := () -> () { value ::= Box#(Int32)(.value = 42) }
