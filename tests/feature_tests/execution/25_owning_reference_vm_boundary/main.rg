Counter := (.count: Int32 = 0)

Resource := (.counter: $&Counter)

implement Deinit<Resource> (
    .deinit = (.self: $&Resource) -> () {
        self&.counter&.count = self&.counter&.count + 1
    }
)

replace := (.target: $&Resource, .counter: $&Counter) -> () {
    target&= Resource(.counter = counter)
}

main := () -> () {
    counter :: Counter = Counter()
    {
        owner :: Resource = Resource(.counter = $&counter)
        replace(.target = $&owner, .counter = $&counter)
        if counter.count != 1 { abort }
    }
    if counter.count != 2 { abort }
}
