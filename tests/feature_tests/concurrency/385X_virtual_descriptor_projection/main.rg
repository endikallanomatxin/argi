Reader#(.T: Type): Contract = (
    .read: (.self: &T) -> (.value: Int32) where reads(self)
)
Cell := (.value: Int32)
implement Reader#(Cell) (
    .read = (.self: &Cell) -> (.value: Int32) { value = self&.value }
)
main := () -> () {
    cell ::= Cell(42)
    reader ::= Virtual#(Reader)(&cell)
    _ = reader.data
}
