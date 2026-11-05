Counter#(.T: Type): Contract = (
    .state: Region#(T)
    .set: (.self: &T) -> () where writes(self.state)
)
Cell := (.value: Int32)
implement Counter#(Cell) (
    .state = region(self),
    .set = (.self: &Cell) -> () {}
)
main := () -> () {
    cell ::= Cell(0)
    counter ::= to_virtual#(Counter)(&cell)
    set(&counter)
}
