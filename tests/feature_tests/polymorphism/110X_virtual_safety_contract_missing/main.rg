Source: Abstract = (
    get(.self: &Self) -> (.value: Int32)
)

Cell: Type = (.value: Int32)

Cell implements Source

get(.self: &Cell) -> (.value: Int32) := { value = self&.value }

main() -> () := {
    cell ::= Cell(42)
    source ::= to_virtual#(Source)(&cell)
}
