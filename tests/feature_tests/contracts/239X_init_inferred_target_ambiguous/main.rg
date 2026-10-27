Box := #(.T: Type) (.value: T)

implement#(.T: Type) Init#(Box#(T), (.value: T)) (
    .Result : Type = Box#(T)
    .init   = (.args: (.value: T)) -> (.result: Result) { result = (.value = args.value) }
)

implement Init#(Box#(Int32), (.value: UInt8)) (
    .Result : Type = Box#(Int32)
    .init   = (.args: (.value: UInt8)) -> (.result: Result) { result = (.value = 0) }
)

main := () -> () {
    byte :: UInt8 = 42
    box ::= Box(.value = byte)
}
