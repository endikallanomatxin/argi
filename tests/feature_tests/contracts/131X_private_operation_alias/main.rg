helper := import ("./helper")

Reader<.T: Type>: Contract = (.read: (.value: &T) -> (.result: Int32))

implement Reader<Int32> (.read = helper._read_integer)

main := () -> () {}
