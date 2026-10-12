Readable#(.item: Type): Contract = (
    read(.source: &Self) -> (.value: item) where {}
)

Cell: Type = (.value: Int32)

Cell satisfies Readable#(Int32)

read(.source: &Cell) -> (.value: Int32) := { value = source&.value }

consume(.source: &Virtual#(Readable#(Int32))) -> (.value: Int32) := {
    value = read(source)
}

main() -> (.status_code: Int32 = 0) := {
    cell ::= Cell(42)
    handle ::= to_virtual#(Readable#(Int32))(&cell)
    if consume(&handle).value != 42 { abort }
}
