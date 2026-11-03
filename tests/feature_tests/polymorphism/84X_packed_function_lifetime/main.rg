Resource := (.value: Int32)
implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {}
)
consume := (.item: Resource) -> () {}

main := () -> () {
    args: inputs_of#(consume) = (.item = Resource(42))
    invoke#(consume)(.args = ~args)
    invoke#(consume)(.args = ~args)
}
