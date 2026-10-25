Counter: Type = (.count: Int32 = 0, .order: Int32 = 0)

Resource: Type = (.counter: $&Counter, .id: Int32)

Args: Type = (.target: $&Resource)

NestedArgs: Type = (.nested: Args)

Pair: Type = (.first: Resource, .second: Resource)

PairArgs: Type = (.target: $&Pair)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        self&.counter&.count = self&.counter&.count + 1
        self&.counter&.order = self&.counter&.order * 10 + self&.id
    }
)

make(.counter: $&Counter, .id: Int32) -> (.result: Resource) := {
    counter&.order = counter&.order * 10 + id
    result = Resource(.counter = counter, .id = id)
}

main() -> (.status_code: Int32 = 0) := {
    counter :: Counter = Counter()
    {
        owner :: Resource = Resource(.counter = $&counter, .id = 1)
        args: NestedArgs = (.nested = (.target = $&owner))
        copied := args
        copied.nested.target&= make(.counter = $&counter, .id = 2)
        if copied.nested.target&.id != 2 { abort }
        if counter.count != 1 or counter.order != 21 { abort }
    }
    if counter.count != 2 or counter.order != 212 { abort }
    {
        owner :: Resource = Resource(.counter = $&counter, .id = 3)
        args: Args = (.target = $&owner)
        deinit(.self = args.target)
        args.target&= Resource(.counter = $&counter, .id = 4)
        if args.target&.id != 4 or counter.count != 3 { abort }
    }
    if counter.count != 4 { abort }
    {
        pair :: Pair = (
            .first  = Resource(.counter = $&counter, .id = 5)
            .second = Resource(.counter = $&counter, .id = 6)
        )
        args: PairArgs = (.target = $&pair)
        sibling := &pair.second.id
        args.target&.first = Resource(.counter = $&counter, .id = 7)
        if sibling&!= 6 or counter.count != 5 { abort }
    }
    if counter.count != 7 { abort }
    status_code = 42
}
