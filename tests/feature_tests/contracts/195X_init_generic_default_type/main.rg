Box := #(.T: Type) (._value: T)

implement#(.T: Type) Init#(Box#(T)) (
    .init = (.value: T = 7) -> (.result: Box#(T)) { result = (._value = value) }
)

Record := (.value: Int32)

main := () -> () { Box#(Record)() }
