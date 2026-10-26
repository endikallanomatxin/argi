Counter := (.drops: Int32 = 0)

Resource := (.counter: $&Counter, .value: Int32)

ReferenceRecord := (.value: $&Resource)

implement Deinit<Resource> (
    .deinit = (.self: $&Resource) -> () { self&.counter&.drops = self&.counter&.drops + 1 }
)

forward := (.source: $&Resource) -> (.result: ReferenceRecord) {
    result.value = source
}

forward_alias := (.source: $&Resource) -> (.result: ReferenceRecord) {
    destination ::= $&result.value
    destination&= source
}

main := () -> (.status_code: Int32) {
    counter :: Counter = Counter()
    {
        owner :: Resource = Resource(.counter = $&counter, .value = 42)
        reference ::= forward(.source = $&owner)
        reference.value&= Resource(.counter = $&counter, .value = 41)
        if counter.drops != 1 { abort }
        if owner.value != 41 { abort }
    }
    if counter.drops != 2 { abort }
    {
        owner :: Resource = Resource(.counter = $&counter, .value = 42)
        reference ::= forward_alias(.source = $&owner)
        deinit(.self = reference.value)
    }
    if counter.drops != 3 { abort }
    status_code = 42
}
