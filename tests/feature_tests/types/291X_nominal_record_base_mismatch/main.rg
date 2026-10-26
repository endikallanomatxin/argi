VertexId := (.value: UIntNative)

accept := (.value: VertexId) -> () {}

main := () -> () {
    raw: UIntNative = 1
    accept(.value = raw)
}
