Value: Type = (.number: Int32)
answer := () -> (.value: Int32) { value = 42 }
answer_value := 42
record: (.inner: (.number: Int32)) = (.inner = (.number = 9))
identity#(.T: Type) := (.value: T) -> (.result: T) { result = value }
