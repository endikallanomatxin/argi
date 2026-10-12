Cell: Type = (.value: Int32)
Reader#(.T: Type): Contract = (.read: (.value: &T) -> (.result: Int32))
read := (.value: &Cell) -> (.result: Int32) { result = value&.value }
satisfies Reader#(Cell)
main := () -> () {}
