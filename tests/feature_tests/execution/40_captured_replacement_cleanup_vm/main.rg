Counter := (.count: Int32 = 0)

Resource := (.counter: $&Counter)

Aliases := (.target: $&Resource, .guard: Resource)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        self&.counter&.count = self&.counter&.count + 1
    }
)

main := () -> (.status_code: Int32 = 0) {
    counter :: Counter = Counter()
    {
        owner :: Resource = Resource(.counter = $&counter)
        aliases: Aliases = (.target = $&owner, .guard = Resource(.counter = $&counter))
        aliases.target&= Resource(.counter = $&counter)
        if counter.count != 1 { abort }
    }
    if counter.count != 3 { abort }
    status_code = 42
}
