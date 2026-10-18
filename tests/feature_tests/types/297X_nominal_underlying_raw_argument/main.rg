VertexId: Type = UIntNative

accept_raw(.value: UIntNative) -> () := {}

main() -> () := {
    vertex: VertexId = 1
    accept_raw(.value = vertex)
}
