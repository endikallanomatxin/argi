Cell := (.value: Int32)

Reader<.T: Type>: Contract = (.read: (.value: &T) -> (.result: Int32))

implement Reader<Cell> (.read = nonexistent_function)

main := () -> () {}
