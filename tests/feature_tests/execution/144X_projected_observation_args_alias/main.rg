Counter := (.count: Int32 = 0)

Resource := (.value: Int32, .counter: $&Counter)

Holder := (.item: Resource)

ObserveArgs := (.owner: $&Holder, .other: &Resource)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () { self&.counter&.count = self&.counter&.count + 1 }
)

observe := (.args: ObserveArgs) -> (.result: Int32) {
    deinit(.self = $&args.owner&.item)
    result = args.other&.value
}

main := () -> (.status_code: Int32) {
    counter :: Counter = Counter()
    holder :: Holder = Holder(.item = Resource(.value = 42, .counter = $&counter))
    status_code = observe(.args = (.owner = $&holder, .other = &holder.item))
}
