Resource := (.value: Int32)

implement Deinit<Resource> (
    .deinit = (.self: $&Resource) -> () {}
)

renew := <.T: Type> (.target: $&T) -> (.result: $&T = target) {
    deinit(.self = target)
    target&= Resource(.value = 2)
}

main := () -> () {
    owner :: Resource = Resource(.value = 1)
    old := renew<.T: Resource>(.target = $&owner)
    if old&.value != 2 { abort }
}
