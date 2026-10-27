Box := #(.T: Type) (.value: T)

BoxInitArgs: Type = #(.T: Type) (.value: T)

implement#(.T: Type) Init#(Box#(T), BoxInitArgs#(T)) (
    .Result : Type = Box#(T)

    .init = BoxInitArgs#(T) -> (.result: Result) { result = (.value = value) }
)

BoxInitArgs2: Type = (.value: UInt8)

implement Init#(Box#(Int32), BoxInitArgs2) (
    .Result : Type = Box#(Int32)

    .init = BoxInitArgs2 -> (.result: Result) { result = (.value = 0) }
)

main := () -> () {
    byte :: UInt8 = 42
    box ::= Box(.value = byte)
}
