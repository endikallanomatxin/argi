Cell := (.value: Int32)

Reader<.T: Type>: Contract = (.read: (.value: &T) -> (.result: Int32))

implement Reader<Cell> (
    .read = (.value: &Cell) -> (.result: Int32) { result = value&.value }
)

main := () -> () { Reader<Cell>.read(7) }
