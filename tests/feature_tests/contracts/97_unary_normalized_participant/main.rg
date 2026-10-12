Readable#(.Other: Type): Contract = (
    read(.other: &Other, .source: &Self) -> (.value: &Int32)
        where depends_on(value, source)
)
Cell: Type = (.value: Int32)
Cell satisfies Readable#(.Other: Cell)
read(.other: &Cell, .source: &Cell) -> (.value: &Int32) := { value = &source&.value }
consume#(.T: Type: Readable#(.Other: Cell))(.other: &Cell, .source: &T) -> (.value: &Int32) := { value = read(other, source).value }
main() -> () := {
    other ::= Cell(7)
    source ::= Cell(42)
    if consume(&other, &source)& != 42 { abort }
    handle ::= to_virtual#(.contract: Readable#(.Other: Cell))(.value = &source)
    if read(&other, &handle)& != 42 { abort }
}
