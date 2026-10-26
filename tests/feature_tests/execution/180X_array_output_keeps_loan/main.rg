Resource := (.value: Int32)

implement Deinit<Resource> (
    .deinit = (.self: $&Resource) -> () {}
)

forward := (.source: &Resource) -> (.result: [1]&Resource) {
    result[0] = source
}

main := () -> () {
    owner :: Resource = Resource(42)
    references ::= forward(.source = &owner)
    deinit(.self = $&owner)
    observed ::= references[0]&.value
}
