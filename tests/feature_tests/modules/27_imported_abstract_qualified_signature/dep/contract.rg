Abstract#(.Value: Type): Contract = (
    .score : (.value: Value) -> (.result: Int32)
)

consume := #(.Value: Type: Abstract) (.value: Value) -> (.result: Int32) {
    result = score(.value = value).result
}
