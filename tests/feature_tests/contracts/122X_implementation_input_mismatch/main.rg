Cell := (.value: Int32)

Reader#(.T: Type): Contract = (.read: (.value: &T) -> (.result: Int32))

read_integer := (.value: Int32) -> (.result: Int32) { result = value }

implement Reader#(Cell) (.read = read_integer)

main := () -> () {}
