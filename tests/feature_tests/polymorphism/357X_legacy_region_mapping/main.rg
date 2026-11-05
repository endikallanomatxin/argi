Counter#(.T: Type): Contract = (
    .state: Region#(T)
    .set: (.self: $&T) -> () where writes(self.state)
)
Cell := (.value: Int32)
implement Counter#(Cell) (.set = (.self: $&Cell) -> () { self&.value = 42 }) where { state(self.value) }
main := () -> () { cell ::= Cell(0) handle ::= to_virtual#(Counter)($&cell) set($&handle) }
