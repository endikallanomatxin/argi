Readable#(.Value: Type): Contract = (
    .read: (.value: &Value) -> (.result: Int32) where {}
)
Box: Type = (.value: Int32)
implement Readable#(Box) (
    .read = (.value: &Box) -> (.result: Int32) { result = value&.value }
)
main := () -> () {
    box ::= Box(1)
    erased :: Virtual#(.contract: Readable) = to_virtual#(.abstract: Readable)(&box)
}
