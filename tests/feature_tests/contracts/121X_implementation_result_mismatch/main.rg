Cell := (.value: Int32)

Reader<.T: Type>: Contract = (
    .Result : Type
    .read   : (.value: &T) -> (.result: Result)
)

read_cell := (.value: &Cell) -> (.result: UInt8) { result = 1 }

implement Reader<Cell> (
    .Result : Type = Int32
    .read   = read_cell
)

main := () -> () {}
