Counter := (.drops: Int32 = 0)

Resource := (.counter: $&Counter, .value: Int32)

ResourceReference := (.value: $&Resource)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () { self&.counter&.drops = self&.counter&.drops + 1 }
)

transfer := (.source: Resource) -> (.result: Resource) {
    relocate(.source = $&source, .destination = $&result)
}

transfer_reference := (.source: ResourceReference) -> (.result: ResourceReference) {
    relocate(.source = $&source, .destination = $&result)
}

main := () -> (.status_code: Int32) {
    counter :: Counter = Counter()
    {
        first ::= Resource(.counter = $&counter, .value = 42)
        second ::= transfer(.source = ~first)
        if second.value != 42 { abort }
    }
    if counter.drops != 1 { abort }
    {
        owner :: Resource = Resource(.counter = $&counter, .value = 42)
        references ::= transfer_reference(.source = (.value = $&owner))
        deinit(.self = references.value)
    }
    if counter.drops != 2 { abort }
    {
        owner :: Resource = Resource(.counter = $&counter, .value = 42)
        references ::= transfer_reference(.source = (.value = $&owner))
        deinit(.self = references.value)
        references.value&= Resource(.counter = $&counter, .value = 42)
    }
    if counter.drops != 4 { abort }
    status_code = 42
}
