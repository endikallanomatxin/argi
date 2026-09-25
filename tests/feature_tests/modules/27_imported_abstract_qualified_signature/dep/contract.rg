Abstract : Abstract = (
    score(.value: Self) -> (.result: Int32)
)

consume(.value: Abstract) -> (.result: Int32) := {
    result = score(.value = value).result
}
