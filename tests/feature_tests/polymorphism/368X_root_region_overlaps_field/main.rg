Counter#(.T: Type): Contract = (
    .whole: Region#(T)
    .part: Region#(T)
    .get: (.self: &T) -> (.result: Int32) where reads(self.whole)
)
Cell := (.value: Int32)
implement Counter#(Cell) (
    .whole = region(self),
    .part = region(self.value),
    .get = (.self: &Cell) -> (.result: Int32) { result = self&.value }
)
main := () -> () {
    cell ::= Cell(7)
    counter ::= to_virtual#(Counter)(&cell)
}
