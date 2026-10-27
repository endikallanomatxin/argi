Box := #(.T: Type) (._value: T)

implement#(.T: Type) Init#(Box#(T), (.value: T = 7)) (
    .Result : Type = Box#(T)
    .init   = (.args: (.value: T = 7)) -> (.result: Result) { result = (._value = args.value) }
)

Record := (.value: Int32)

main := () -> () { Box#(Record)() }
