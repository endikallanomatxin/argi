Counter := (.count: Int32 = 0)

Resource := (.counter: $&Counter)

Holder := (.item: Resource, .sibling: Resource)

implement Deinit<Resource> (
    .deinit = (.self: $&Resource) -> () { self&.counter&.count = self&.counter&.count + 1 }
)

observe := (.self: $&Holder, .other: &Resource) -> () {
    snapshot ::= other&.counter&.count
    deinit(.self = $&self&.item)
    if snapshot != 0 { abort }
}

main := () -> (.status_code: Int32) {
    counter :: Counter = Counter()
    {
        holder :: Holder = Holder(
            .item = Resource(.counter = $&counter), .sibling = Resource(.counter = $&counter)
        )
        observe(.self = $&holder, .other = &holder.item)
    }
    if counter.count != 2 { abort }
    status_code = 42
}
