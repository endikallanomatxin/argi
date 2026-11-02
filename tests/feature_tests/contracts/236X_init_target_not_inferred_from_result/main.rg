Box := #(.T: Type) (.value: T)

BoxInitArgs: Type = #(.T: Type) ()

implement#(.T: Type) Init#(Box#(T), BoxInitArgs#(T)) (
    .Result : Type = Box#(Int32)

    .init = BoxInitArgs#(T) -> (.result: Result) { result = (.value = 42) }
)

main := () -> () { box ::= Box() }
