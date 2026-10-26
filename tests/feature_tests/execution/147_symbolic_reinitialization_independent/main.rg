Resource := (.value: Int32)

implement Deinit<Resource> (
    .deinit = (.self: $&Resource) -> () {}
)

cycle := (.target: $&Resource, .other: &Resource) -> () {
    deinit(.self = target)
    target&= Resource(.value = 2)
    if other&.value != 42 { abort }
}

main := () -> (.status_code: Int32) {
    owner :: Resource = Resource(.value = 1)
    independent :: Resource = Resource(.value = 42)
    cycle(.target = $&owner, .other = &independent)
    if owner.value != 2 { abort }
    status_code = 42
}
