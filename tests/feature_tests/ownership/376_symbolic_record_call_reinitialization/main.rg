drops :: Int32 = 0

Resource := (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () { drops = drops + 1 }
)

Args := (.target: $&Resource)

initialize := (.args: Args) -> () { args.target&= Resource(.value = 2) }

cycle := (.target: $&Resource) -> () {
    deinit(.self = target)
    args: Args = (.target = target)
    initialize(.args = args)
    if args.target&.value != 2 { abort }
    deinit(.self = args.target)
}

main := () -> (.status_code: Int32 = 0) {
    {
        owner :: Resource = Resource(.value = 1)
        cycle(.target = $&owner)
    }
    if drops != 2 { abort }
    status_code = 42
}
