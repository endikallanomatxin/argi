Counter := (.count: Int32 = 0)

Resource := (.counter: $&Counter)

Pair := (.first: Resource, .second: Resource)

implement Deinit<Resource> (
    .deinit = (.self: $&Resource) -> () {
        self&.counter&.count = self&.counter&.count + 1
    }
)

initialize := (.target: $&Resource, .counter: $&Counter) -> () {
    target&= Resource(.counter = counter)
}

initialize_pair := (.target: $&Pair, .counter: $&Counter) -> () {
    target&.first = Resource(.counter = counter)
}

initialize_forwarded := (.target: $&Resource, .counter: $&Counter) -> () {
    initialize(.target = target, .counter = counter)
}

initialize_args := (.args: (.target: $&Resource, .counter: $&Counter)) -> () {
    args.target&= Resource(.counter = args.counter)
}

Outcome: Type = (..initialized, ..unchanged)

initialize_conditionally := (.target: $&Resource, .counter: $&Counter, .enabled: Bool) -> (
    .result : Outcome
) {
    if enabled {
        initialize_forwarded(.target = target, .counter = counter)
        result = ..initialized
        return
    }
    result = ..unchanged
}

main := () -> (.status_code: Int32 = 0) {
    counter :: Counter = Counter()
    {
        owner :: Resource = Resource(.counter = $&counter)
        target := $&owner
        deinit(.self = target)
        initialize(.target = target, .counter = $&counter)
    }
    if counter.count != 2 { abort }
    {
        owner :: Pair = Pair(
            .first = Resource(.counter = $&counter), .second = Resource(.counter = $&counter)
        )
        deinit(.self = $&owner.first)
        initialize_pair(.target = $&owner, .counter = $&counter)
    }
    if counter.count != 5 { abort }
    {
        owner :: Resource = Resource(.counter = $&counter)
        deinit(.self = $&owner)
        initialize_forwarded(.target = $&owner, .counter = $&counter)
    }
    if counter.count != 7 { abort }
    {
        owner :: Resource = Resource(.counter = $&counter)
        deinit(.self = $&owner)
        initialize_args(.args = (.target = $&owner, .counter = $&counter))
    }
    if counter.count != 9 { abort }
    {
        owner :: Resource = Resource(.counter = $&counter)
        deinit(.self = $&owner)
        initialize_conditionally(.target = $&owner, .counter = $&counter, .enabled = true)
    }
    if counter.count != 11 { abort }
    {
        owner :: Resource = Resource(.counter = $&counter)
        deinit(.self = $&owner)
        initialize_conditionally(.target = $&owner, .counter = $&counter, .enabled = false)
    }
    if counter.count != 12 { abort }
    status_code = 42
}
