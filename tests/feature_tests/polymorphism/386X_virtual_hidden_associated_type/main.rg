Reader#(.R: Type): Contract = (
    .Item: Type
    .read: (.receiver: &R) -> (.item: Item) where {}
)
Factory#(.R: Type): Contract = (
    .make: (.receiver: &R) -> (.reader: Virtual#(Reader#(.Item: R))) where depends_on(reader, receiver)
)
Box := (.value: Int32)
implement Reader#(Box) (
    .Item: Type = Box
    .read = (.receiver: &Box) -> (.item: Box) { item = receiver& }
)
implement Factory#(Box) (
    .make = (.receiver: &Box) -> (.reader: Virtual#(Reader#(.Item: Box))) {
        reader = Virtual#(Reader#(.Item: Box))(receiver)
    }
)
main := () -> () {
    box ::= Box(1)
    factory ::= Virtual#(Factory)(&box)
    _ = factory
}
