Resource := (.value: Int32)

Holder := (.reference: $&Resource)

implement Deinit#(Resource) (.deinit = (.self: $&Resource) -> () {})

set_reference := (.holder: $&Holder, .other: $&Resource, .replace: Bool) -> () {
    if replace { holder&.reference = other }
}

check := (.holder: $&Holder, .other: $&Resource) -> () {
    set_reference(.holder = holder, .other = other, .replace = true)
    deinit(.self = other)
    value ::= holder&.reference&.value
    if value == 2 { abort }
}

main := () -> (.status_code: Int32) {
    owner :: Resource = Resource(.value = 1)
    other :: Resource = Resource(.value = 2)
    holder :: Holder = Holder(.reference = $&owner)
    check(.holder = $&holder, .other = $&other)
    status_code = 42
}
