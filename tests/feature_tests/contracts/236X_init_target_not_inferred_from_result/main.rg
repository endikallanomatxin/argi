Box := #(.T: Type) (.value: T)

implement#(.T: Type) Init#(Box#(T), ()) (
    .Result : Type = Box#(Int32)
    .init   = (.args: ()) -> (.result: Result) { result = (.value = 42) }
)

main := () -> () { box ::= Box() }
