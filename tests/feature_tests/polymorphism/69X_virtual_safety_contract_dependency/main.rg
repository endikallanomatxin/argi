Source: Abstract = (
    get(.self: &Self, .other: &Int32) -> (.value: &Int32)
    where depends_on(value, self)
)

Cell: Type = (.value: Int32)

Cell implements Source

get(.self: &Cell, .other: &Int32) -> (.value: &Int32) := {
    value = other
}

main() -> () := {
    cell ::= Cell(42)
    source ::= to_virtual#(Source)(&cell)
}
