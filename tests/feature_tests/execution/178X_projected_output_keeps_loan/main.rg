Resource := (.value: Int32)

ReferenceRecord := (.value: &Resource)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {}
)

forward := (.source: &Resource) -> (.result: ReferenceRecord) {
    result.value = source
}

main := () -> () {
    owner :: Resource = Resource(42)
    reference ::= forward(.source = &owner)
    deinit(.self = $&owner)
    observed ::= reference.value&.value
}
