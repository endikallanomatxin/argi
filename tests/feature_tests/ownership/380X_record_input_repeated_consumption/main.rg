Resource := (.value: Int32)

Access := (.target: $&Resource, .other: $&Resource)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {}
)

cycle := (.args: Access) -> () {
    deinit(.self = args.target)
    deinit(.self = args.target)

}

main := () -> () {
    owner :: Resource = Resource(.value = 1)
    other :: Resource = Resource(.value = 2)
    cycle(.args = (.target = $&owner, .other = $&other))
}
