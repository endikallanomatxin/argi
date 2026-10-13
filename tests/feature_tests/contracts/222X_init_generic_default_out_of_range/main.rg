Box#(.T: Type): Type = (.value: T, .small: Int8)
implement#(.T: Type) Init#(Box#(T)) (
    .Args: Type = (.value: T, .small: Int8 = 128)
    .Result: Type = Box#(T)
    .init = (.args: Args) -> (.result: Result) { result = (.value = args.value, .small = args.small) }
)
main := () -> () { value ::= Box#(Int32)(.value = 42) }
