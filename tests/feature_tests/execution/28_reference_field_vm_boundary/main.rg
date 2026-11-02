Counter := (.count: Int32 = 0)

Resource := (.counter: $&Counter)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        self&.counter&.count = self&.counter&.count + 1
    }
)

Holder := (.owned: Resource, .target: $&Resource)

main := () -> () {
    counter :: Counter = Counter()
    {
        owner :: Resource = Resource(.counter = $&counter)
        holder :: Holder = Holder(.owned = Resource(.counter = $&counter), .target = $&owner)
        holder.target&= Resource(.counter = $&counter)
        if counter.count != 1 { abort }
    }
    if counter.count != 3 { abort }
}
