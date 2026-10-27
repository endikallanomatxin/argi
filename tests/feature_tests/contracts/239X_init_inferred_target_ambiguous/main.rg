Box := #(.T: Type) (.value: T)

implement#(.T: Type) Init#(Box#(T)) (
    .init = (.value: T) -> (.result: Box#(T)) { result = (.value = value) }
)

implement Init#(Box#(Int32)) (
    .init = (.value: UInt8) -> (.result: Box#(Int32)) { result = (.value = 0) }
)

main := () -> () {
    byte :: UInt8 = 42
    box ::= Box(.value = byte)
}
