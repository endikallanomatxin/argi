Cell := (.value: Int32)

Reader<.T: Type>: Contract = (.read: (.value: &T) -> (.result: Int32))

read_cell := (.value: &Cell) -> (.result: Int32) { result = value&.value }

implement Reader<Cell> (
    .read = read_cell
    .read = read_cell
)

main := () -> () {}
