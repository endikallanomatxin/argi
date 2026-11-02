Box := #(.T: Type) (._value: T)

BoxInitArgs: Type = #(.T: Type) (.value: T = 7)

implement#(.T: Type) Init#(Box#(T), BoxInitArgs#(T)) (
    .Result : Type = Box#(T)

    .init = BoxInitArgs#(T) -> (.result: Result) { result = (._value = value) }
)

Record := (.value: Int32)

main := () -> () { Box#(Record)() }
