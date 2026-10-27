Resource := (.id: Int32)

Args := (.target: $&Resource)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {}
)

initialize := (.args: Args) -> () {
    args.target&= Resource(.id = 42)
}

initialize_borrowed := (.args: &Args) -> () {
    initialize(.args = args&)
}

main := () -> (.status_code: Int32 = 0) {
    owner :: Resource = Resource(.id = 1)
    args: Args = (.target = $&owner)
    copied := args
    deinit(.self = args.target)
    initialize_borrowed(.args = &args)
    status_code = copied.target&.id
}
