VertexId := (.value: UIntNative)

EdgeId := (.value: UIntNative)

accept(.value: VertexId) -> () := {}

main() -> () := {
    edge: EdgeId = (.value = 1)
    accept(.value = edge)
}
