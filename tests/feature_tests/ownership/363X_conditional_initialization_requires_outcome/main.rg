Resource := (.value: Int32)

implement Deinit<Resource> (
    .deinit = (.self: $&Resource) -> () {}
)

initialize := (.target: $&Resource, .enabled: Bool) -> () {
    if enabled { target&= Resource(.value = 42) }
}

main := () -> () {
    owner :: Resource = Resource(.value = 1)
    deinit(.self = $&owner)
    initialize(.target = $&owner, .enabled = true)
}
