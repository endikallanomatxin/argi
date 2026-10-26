Resource := (.value: Int32)

implement Deinit<Resource> (
    .deinit = (.self: $&Resource) -> () {
        if self&.value < 0 { abort }
        self&.value = -1
    }
)

cycle := (.target: $&Resource) -> () {
    deinit(.self = target)
    target&= Resource(.value = 42)
    if target&.value != 42 { abort }
    deinit(.self = target)
}

main := () -> (.status_code: Int32 = 0) {
    {
        owner :: Resource = Resource(.value = 1)
        cycle(.target = $&owner)
    }
    status_code = 42
}
