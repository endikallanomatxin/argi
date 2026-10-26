Resource := (.value: Int32)

implement Deinit<Resource> (
    .deinit = (.self: $&Resource) -> () {}
)

cycle := (.target: $&Resource) -> () {
    old := target
    deinit(.self = target)
    target&= Resource(.value = 2)
    deinit(.self = old)
}

main := () -> () {
    owner :: Resource = Resource(.value = 1)
    cycle(.target = $&owner)
}
