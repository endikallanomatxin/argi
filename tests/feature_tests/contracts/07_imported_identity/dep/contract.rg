Capability: Contract = (
    score(.value: Self) -> (.result: Int32)
)

consume(.value: Capability) -> (.result: Int32) := {
    result = score(.value = value).result
}
