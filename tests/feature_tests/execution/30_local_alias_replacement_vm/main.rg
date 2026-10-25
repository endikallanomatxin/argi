Counter: Type = (.count: Int32 = 0, .order: Int32 = 0)

Resource: Type = (.counter: $&Counter, .id: Int32)

Pair: Type = (.first: Resource, .second: Resource)

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

forward(.value: $&Resource) -> (.result: $&Resource) := {
    result = value
}

forward_large(.value: &Counter) -> (.result: (.padding: [40]Int32, .target: &Counter)) := {
    result = (.padding = zeroed#(.t: [40]Int32)(), .target = value)
}

main() -> (.status_code: Int32 = 0) := {
    counter :: Counter = Counter()
    {
        owner :: Resource = Resource(.counter = $&counter, .id = 1)
        alias := $&owner
        chain := forward(.value = alias)
        reborrow := $&chain&
        reborrow&= make(.counter = $&counter, .id = 2)
        if counter.count != 1 or counter.order != 21 { abort }
        if reborrow&.id != 2 { abort }
    }
    if counter.count != 2 or counter.order != 212 { abort }
    {
        pair :: Pair = Pair(
            .first  = Resource(.counter = $&counter, .id = 3)
            .second = Resource(.counter = $&counter, .id = 4)
        )
        alias := $&pair
        sibling := &pair.second.id
        first := $&alias&.first
        first&= Resource(.counter = $&counter, .id = 5)
        if sibling&!= 4 or counter.count != 3 { abort }
    }
    if counter.count != 5 { abort }
    {
        owner :: Resource = Resource(.counter = $&counter, .id = 6)
        alias := $&owner
        deinit(.self = alias)
        alias&= Resource(.counter = $&counter, .id = 7)
        if alias&.id != 7 or counter.count != 6 { abort }
    }
    if counter.count != 7 { abort }
    {
        first :: Resource = Resource(.counter = $&counter, .id = 8)
        second :: Resource = Resource(.counter = $&counter, .id = 9)
        alias := $&first
        deinit(.self = $&second)
        alias&= Resource(.counter = $&counter, .id = 0)
        if counter.count != 9 { abort }
    }
    if counter.count != 10 { abort }
    {
        first :: Resource = Resource(.counter = $&counter, .id = 1)
        second :: Resource = Resource(.counter = $&counter, .id = 2)
        target :: $&Resource = $&first
        indirect := $&target
        indirect&= $&second
        observed := indirect&
        if observed&.id != 2 { abort }
    }
    if counter.count != 12 { abort }
    large := forward_large(.value = &counter)
    if large.target&.count != 12 { abort }
    {
        owner :: Resource = Resource(.counter = $&counter, .id = 3)
        references: (.target: $&Resource) = (.target = $&owner)
        copied := references
        selected := copied.target
        selected&= Resource(.counter = $&counter, .id = 4)
        if counter.count != 13 { abort }
    }
    if counter.count != 14 { abort }
    status_code = 42
}
