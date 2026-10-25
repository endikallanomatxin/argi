Counter: Type = (.count: Int32 = 0)

Resource: Type = (.counter: $&Counter)

Holder: Type = (.item: Resource, .sibling: Resource)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () { self&.counter&.count = self&.counter&.count + 1 }
)

keep(.self: $&Holder, .value: &Resource) -> (.result: &Resource) := {
    deinit(.self = $&self&.item)
    result = value
}

observe(.self: $&Holder, .other: &Resource) -> () := {
    if keep(.self = self, .value = other)&.counter&.count == 0 { abort }
}

main() -> (.status_code: Int32) := {
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
