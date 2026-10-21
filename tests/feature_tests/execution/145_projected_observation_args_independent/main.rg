Counter: Type = (.count: Int32 = 0)

Resource: Type = (.value: Int32, .counter: $&Counter)

Holder: Type = (.item: Resource)

ObserveArgs: Type = (.owner: $&Holder, .other: &Resource)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () { self&.counter&.count = self&.counter&.count + 1 }
)

observe(.args: ObserveArgs) -> (.result: Int32) := {
    deinit(.self = $&args.owner&.item)
    result = args.other&.value
}

main() -> (.status_code: Int32) := {
    counter :: Counter = Counter()
    {
        holder :: Holder = Holder(.item = Resource(.value = 17, .counter = $&counter))
        independent :: Resource = Resource(.value = 42, .counter = $&counter)
        if observe(.args = (.owner = $&holder, .other = &independent)) != 42 { abort }
    }
    if counter.count != 2 { abort }
    status_code = 42
}
