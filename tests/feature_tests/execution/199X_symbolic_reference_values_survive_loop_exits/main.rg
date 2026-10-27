Resource := (.value: Int32)

Holder := (.reference: $&Resource)

implement Deinit#(Resource) (.deinit = (.self: $&Resource) -> () {})

check := (.holder: $&Holder, .other: $&Resource, .replace: Bool) -> () {
    while replace {
        holder&.reference = other
        break
    }
    deinit(.self = other)
    value ::= holder&.reference&.value
    if value == 2 { abort }
}

main := () -> (.status_code: Int32) {
    owner :: Resource = Resource(.value = 1)
    other :: Resource = Resource(.value = 2)
    holder :: Holder = Holder(.reference = $&owner)
    check(.holder = $&holder, .other = $&other, .replace = true)
    status_code = 42
}
