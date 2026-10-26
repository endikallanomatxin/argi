Resource := (.value: Int32)

implement Deinit<Resource> (
    .deinit = (.self: $&Resource) -> () {}
)

consume := (.target: $&Resource) -> (.result: Int32 = 42) {
    deinit(.self = target)
}

repeat := <.T: Type> (.target: $&T) -> (.result: Int32 = consume(.target = target)) {
    deinit(.self = target)
}

main := () -> (.status_code: Int32 = 0) {
    owner :: Resource = Resource(.value = 1)
    status_code = repeat<.T: Resource>(.target = $&owner)
}
