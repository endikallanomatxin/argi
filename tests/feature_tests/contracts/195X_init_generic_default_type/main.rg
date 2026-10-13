Box#(.T: Type): Type = (._value: T)
implement#(.T: Type) Init#(Box#(T)) (
    .Args: Type = (.value: T = 7)
    .Result: Type = Box#(T)
    .init = (.args: Args) -> (.result: Result) { result = (._value = args.value) }
)
Record: Type = (.value: Int32)
main := () -> () { Box#(Record)() }
