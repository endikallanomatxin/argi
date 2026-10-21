Counter: Type = (.count: Int32 = 0)

Resource: Type = (.value: Int32, .counter: $&Counter)

Holder: Type = (.item: Resource, .sibling: Resource)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () { self&.counter&.count = self&.counter&.count + 1 }
)

observe(.self: $&Holder, .other: &Resource) -> (.result: Int32) := {
    deinit(.self = $&self&.item)
    result = other&.value
}

main() -> (.status_code: Int32) := {
    counter :: Counter = Counter()
    {
        holder :: Holder = Holder(
            .item    = Resource(.value = 17, .counter = $&counter)
            .sibling = Resource(.value = 18, .counter = $&counter)
        )
        independent :: Resource = Resource(.value = 42, .counter = $&counter)
        result ::= observe(.self = $&holder, .other = &independent)
        if result != 42 { abort }
    }
    if counter.count != 3 { abort }
    status_code = 42
}
