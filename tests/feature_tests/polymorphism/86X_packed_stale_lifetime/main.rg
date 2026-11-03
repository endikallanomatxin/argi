Resource := (.value: Int32)
implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {}
)
consume := (.item: Resource) -> () {}
forward := (.source: &Resource) -> (.result: &Resource) { result = source }

main := () -> () {
    prepared: inputs_of#(consume) = (.item = Resource(42))
    args: inputs_of#(forward) = (.source = &prepared.item)
    borrowed := invoke#(forward)(.args = ~args)
    invoke#(consume)(.args = ~prepared)
    observed ::= borrowed&.value
}
