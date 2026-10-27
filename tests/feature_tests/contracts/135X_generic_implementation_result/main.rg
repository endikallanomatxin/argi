Copyable#(.Value: Type): Contract = (
    .Result : Type
    .copy   : (.value: Value) -> (.result: Result)
)

implement#(.T: Type) Copyable#(T) (
    .Result : Type = T
    .copy   = (.value: T) -> (.result: UInt8) { result = 1 }
)

main := () -> () {
    Copyable#(Int32).copy(42)
}
