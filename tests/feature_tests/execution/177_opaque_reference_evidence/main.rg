Counter := (.drops: Int32 = 0)

Resource := (.counter: $&Counter)

ReferenceRecord := (.value: $&Resource)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () { self&.counter&.drops = self&.counter&.drops + 1 }
)

main := () -> (.status_code: Int32) {
    counter :: Counter = Counter()
    {
        owner :: Resource = Resource(.counter = $&counter)
        domain :: UInt8 = 0
        storage :: ReferenceRecord
        trusted_opaque_move_in(
            .storage = $&domain, .destination = $&storage, .source = (.value = $&owner)
        )
        result ::= trusted_opaque_move_out(.storage = $&domain, .slot = $&storage)
        trusted_opaque_mark_empty(.storage = $&domain)
        result.value&= Resource(.counter = $&counter)
    }
    if counter.drops != 2 { abort }
    status_code = 42
}
