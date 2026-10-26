Query<.Value: Type>: Contract = (
    .query : (.value: Value) -> (.result: Int32)
)

implement Query<Int32> (
    .query = (.value: Int32) -> (.result: Int32) { result = value + 1 }
)
