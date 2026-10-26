Resource := (.value: Int32)

Access := (.target: $&Resource, .other: $&Resource)

implement Deinit<Resource> (
    .deinit = (.self: $&Resource) -> () { self&.value = -1 }
)

cycle := (.args: Access) -> () {
    old: Access = args
    deinit(.self = args.target)
    args.target&= Resource(.value = 42)
    if old.target&.value == 42 { abort }
    deinit(.self = args.target)

}

main := () -> () {
    owner :: Resource = Resource(.value = 1)
    other :: Resource = Resource(.value = 2)
    cycle(.args = (.target = $&owner, .other = $&other))
}
