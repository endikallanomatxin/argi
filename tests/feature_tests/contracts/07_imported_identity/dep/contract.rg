Capability#(.Participant: Type): Contract = (
    .score: (.value: Participant) -> (.result: Int32)
)
consume#(.Value: Type: Capability) := (.value: Value) -> (.result: Int32) {
    result = score(.value = value).result
}
