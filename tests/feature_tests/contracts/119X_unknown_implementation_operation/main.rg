Cell: Type = (.value: Int32)
Reader#(.T: Type): Contract = (.read: (.value: &T) -> (.result: Int32))
read_cell := (.value: &Cell) -> (.result: Int32) { result = value&.value }
implement Reader#(Cell) (.write = read_cell)
main := () -> () {}
