Counter := (.count: Int32 = 0)

Resource := (.counter: $&Counter)

Holder := (.item: Resource, .sibling: Resource)

implement Deinit<Resource> (
    .deinit = (.self: $&Resource) -> () { self&.counter&.count = self&.counter&.count + 1 }
)

renew := (.self: $&Holder, .counter: $&Counter) -> () {
    target ::= $&self&.item
    historical ::= target
    deinit(.self = target)
    target&= Resource(.counter = counter)
    deinit(.self = historical)
}

main := () -> (.status_code: Int32) {
    counter :: Counter = Counter()
    {
        holder :: Holder = Holder(
            .item = Resource(.counter = $&counter), .sibling = Resource(.counter = $&counter)
        )
        renew(.self = $&holder, .counter = $&counter)
    }
    if counter.count != 3 { abort }
    status_code = 42
}
