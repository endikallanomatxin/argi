float_identity#(.T: Type: Float) := (.value: T) -> (.result: T) { result = value }
main := () -> () { value :: Int32 = 7 float_identity(value) }
