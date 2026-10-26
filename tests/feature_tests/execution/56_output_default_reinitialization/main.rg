Resource := (.value: Int32)

implement Deinit<Resource> (
    .deinit = (.self: $&Resource) -> () {
        if self&.value < 0 { abort }
        self&.value = -1
    }
)

consume := (.target: $&Resource) -> (.result: Int32 = 42) {
    deinit(.self = target)
}

cycle := <.T: Type> (.target: $&T, .next: T) -> (.result: Int32 = consume(.target = target)) {
    target&= ~next
    if target&.value != 2 { abort }
    deinit(.self = target)
}

main := () -> (.status_code: Int32 = 0) {
    {
        owner :: Resource = Resource(.value = 1)
        status_code = cycle<.T: Resource>(.target = $&owner, .next = Resource(.value = 2))
    }
}
