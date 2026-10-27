Box := #(.T: Type) (.value: T)

implement#(.T: Type) Init#(Box#(T)) (
    .init = () -> (.result: Box#(Int32)) { result = (.value = 42) }
)

main := () -> () { box ::= Box() }
