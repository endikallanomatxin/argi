Counter: Type = (.count: Int32 = 0)

Resource: Type = (.counter: $&Counter)

Args: Type = (.target: $&Resource, .counter: $&Counter)

NestedArgs: Type = (.inner: Args)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        self&.counter&.count = self&.counter&.count + 1
    }
)

initialize(.args: Args) -> () := {
    args.target&= Resource(.counter = args.counter)
}

initialize_nested(.args: NestedArgs) -> () := {
    initialize(.args = args.inner)
}

initialize_borrowed(.args: &Args) -> () := {
    initialize(.args = args&)
}

main() -> (.status_code: Int32 = 0) := {
    counter :: Counter = Counter()
    {
        owner :: Resource = Resource(.counter = $&counter)
        args: Args = (.target = $&owner, .counter = $&counter)
        deinit(.self = args.target)
        initialize(.args = args)
        args.target&.counter&.count = args.target&.counter&.count + 10
    }
    if counter.count != 12 { abort }
    {
        owner :: Resource = Resource(.counter = $&counter)
        args: NestedArgs = (.inner = (.target = $&owner, .counter = $&counter))
        deinit(.self = args.inner.target)
        initialize_nested(.args = args)
        args.inner.target&.counter&.count = args.inner.target&.counter&.count + 10
    }
    if counter.count != 24 { abort }
    {
        owner :: Resource = Resource(.counter = $&counter)
        args: Args = (.target = $&owner, .counter = $&counter)
        deinit(.self = args.target)
        initialize_borrowed(.args = &args)
        args.target&.counter&.count = args.target&.counter&.count + 10
    }
    if counter.count != 36 { abort }
    status_code = 42
}
