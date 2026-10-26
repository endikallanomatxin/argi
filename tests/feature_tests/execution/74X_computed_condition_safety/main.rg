Resource := (.value: Int32)

implement Deinit<Resource> (
    .deinit = (.self: $&Resource) -> () {}
)

invalid := () -> (.ok: Bool = true) {
    owner :: Resource = Resource(.value = 1)
    deinit(.self = $&owner)
    deinit(.self = $&owner)
}

main := () -> () { #if invalid() {} }
