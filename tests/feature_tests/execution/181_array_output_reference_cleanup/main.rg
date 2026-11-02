Counter := (.drops: Int32 = 0)

Resource := (.counter: $&Counter)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () { self&.counter&.drops = self&.counter&.drops + 1 }
)

forward := (.source: $&Resource) -> (.result: [1] $&Resource) {
    result[0] = source
}

forward_alias := (.source: $&Resource) -> (.result: [1] $&Resource) {
    destination ::= $&result[0]
    destination&= source
}

forward_nested := (.source: $&Resource) -> (.result: (.values: [1] $&Resource)) {
    result.values[0] = source
}

main := () -> (.status_code: Int32) {
    counter :: Counter = Counter()
    {
        owner :: Resource = Resource(.counter = $&counter)
        references ::= forward(.source = $&owner)
        references[0]&= Resource(.counter = $&counter)
    }
    if counter.drops != 2 { abort }
    {
        owner :: Resource = Resource(.counter = $&counter)
        references ::= forward_alias(.source = $&owner)
        deinit(.self = references[0])
    }
    if counter.drops != 3 { abort }
    {
        owner :: Resource = Resource(.counter = $&counter)
        references ::= forward_nested(.source = $&owner)
        deinit(.self = references.values[0])
    }
    if counter.drops != 4 { abort }
    status_code = 42
}
