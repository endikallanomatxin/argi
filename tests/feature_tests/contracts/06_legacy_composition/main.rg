Base: Abstract = (
    read(.source: &Self) -> (.value: Int32) where {}
)

Combined: Contract = (Base)

Cell: Type = (.value: Int32)

Cell satisfies Combined

read(.source: &Cell) -> (.value: Int32) := { value = source&.value }

consume(.source: Combined) -> (.value: Int32) := { value = read(&source) }

main() -> (.status_code: Int32 = 0) := {
    if consume(Cell(42)).value != 42 { abort }
}
