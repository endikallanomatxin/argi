VertexId: Type = UIntNative

EdgeId: Type = UIntNative

accept(.value: VertexId) -> () := {}

main() -> () := {
    edge: EdgeId = 1
    accept(.value = edge)
}
