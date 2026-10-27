VertexId := (.value: UIntNative)

accept_raw := (.value: UIntNative) -> () {}

main := () -> () {
    vertex: VertexId = (.value = 1)
    accept_raw(.value = vertex)
}
