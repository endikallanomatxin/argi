Counter := (.drops: Int32 = 0)

Resource := (.counter: $&Counter, .value: Int32)

Pair := (.first: Resource, .second: Resource)

Container := (.counter: $&Counter, .values: [2]Int32)

implement Deinit<Container> (
    .deinit = (.self: $&Container) -> () {
        self&.counter&.drops = self&.counter&.drops + 1
    }
)

implement Deinit<Resource> (
    .deinit = (.self: $&Resource) -> () {
        self&.counter&.drops = self&.counter&.drops + 1
    }
)

main := () -> (.status_code: Int32) {
    counter :: Counter = Counter()
    {
        resources :: [2]Resource
        resources[0] = Resource(.counter = $&counter, .value = 42)
        if resources[0].value != 42 { abort }
        if counter.drops != 0 { abort }
    }
    if counter.drops != 1 { abort }
    {
        resources :: [2]Resource
        resources[0].counter = $&counter
        resources[0].value = 40
        resources[1] = Resource(.counter = $&counter, .value = 2)
        if resources[0].value + resources[1].value != 42 { abort }
    }
    if counter.drops != 3 { abort }
    {
        pairs :: [2]Pair
        pairs[0].first = Resource(.counter = $&counter, .value = 42)
        if pairs[0].first.value != 42 { abort }
    }
    if counter.drops != 4 { abort }
    {
        containers :: [1]Container
        containers[0].counter = $&counter
        containers[0].values[0] = 40
        containers[0].values[1] = 2
        if containers[0].values[0] + containers[0].values[1] != 42 { abort }
    }
    if counter.drops != 5 { abort }
    status_code = 42
}
