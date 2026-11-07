Counter#(.T: Type): Contract = (
    .state: Region#(T)
    .get: (.self: &T) -> (.result: Int32) where reads(self.state)
    .set: (.self: $&T, .value: Int32) -> () where writes(self.state)
)
Cell := (.value: Int32)
implement Counter#(Cell) (
    .state = region(self),
    .get = (.self: &Cell) -> (.result: Int32) { result = self&.value },
    .set = (.self: $&Cell, .value: Int32) -> () { self&.value = value }
)
make := (.cell: $&Cell) -> (.result: Virtual#(Counter)) {
    result = Virtual#(Counter)(cell)
}
main := () -> () {
    cell ::= Cell(7)
    counter ::= make($&cell)
    if get(&counter) != 7 { abort }
    set($&counter, 42)
    if get(&counter) != 42 { abort }
}
