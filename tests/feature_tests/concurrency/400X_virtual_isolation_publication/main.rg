Observe#(.R: Type): Contract = (
    .observe: (.receiver: R) -> (.value: Int32) where { no_access() isolated() }
)
Cell := (.value: Int32)
global :: Int32 = 0
implement Observe#(&Cell) (
    .observe = (.receiver: &Cell) -> (.value: Int32) { value = global }
)
main := () -> () {
    cell ::= Cell(42)
    view ::= Virtual#(Observe)(&cell)
    _ = view
}
