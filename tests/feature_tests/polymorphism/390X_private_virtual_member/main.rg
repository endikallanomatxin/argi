api := import("./api")
Cell := (.value: Int32)
implement api.Reader#(&Cell) (
    ._read = (.receiver: &Cell) -> (.value: Int32) { value = receiver&.value }
)
main := () -> () {
    cell ::= Cell(42)
    view ::= Virtual#(api.Reader)(&cell)
    if view._read().value != 42 { abort }
}
