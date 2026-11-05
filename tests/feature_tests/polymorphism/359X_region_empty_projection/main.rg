Counter#(.T: Type): Contract = (
    .state: Region#(T)
    .set: (.self: $&T) -> () where writes(self.state)
)
Cell := (.value: Int32)
implement Counter#(Cell) (.state = region(), .set = (.self: $&Cell) -> () { self&.value = 42 })
main := () -> () {
    cell ::= Cell(0)
    handle ::= to_virtual#(Counter)($&cell)
    set($&handle)
}
