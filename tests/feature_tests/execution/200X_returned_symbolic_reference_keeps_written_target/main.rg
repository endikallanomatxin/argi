Resource := (.value: Int32)

Holder := (.reference: $&Resource)

implement Deinit<Resource> (.deinit = (.self: $&Resource) -> () {})

load_reference := (.holder: &Holder) -> (.result: $&Resource) { result = holder&.reference }

check := (.holder: $&Holder, .other: $&Resource) -> () {
    holder&.reference = other
    loaded ::= load_reference(.holder = holder)
    deinit(.self = other)
    value ::= loaded&.value
    if value == 2 { abort }
}

main := () -> (.status_code: Int32) {
    owner :: Resource = Resource(.value = 1)
    other :: Resource = Resource(.value = 2)
    holder :: Holder = Holder(.reference = $&owner)
    check(.holder = $&holder, .other = $&other)
    status_code = 42
}
