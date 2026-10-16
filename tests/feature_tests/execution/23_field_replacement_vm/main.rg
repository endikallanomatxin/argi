Counter: Type = (.count: Int32 = 0, .order: Int32 = 0)

Tracked: Type = (.counter: $&Counter, .id: Int32)

Result: Type = (..some Tracked, ..none)

implement Deinit#(Tracked) (
    .deinit = (.self: $&Tracked) -> () {
        self&.counter&.count = self&.counter&.count + 1
        self&.counter&.order = self&.counter&.order * 10 + self&.id
    }
)

make(.counter: $&Counter, .id: Int32) -> (.result: Tracked) := {
    index :: Int32 = 0
    while index < 1 { index = index + 1 }
    counter&.order = counter&.order * 10 + id
    result = Tracked(.counter = counter, .id = id)
}

Pair: Type = (.first: Tracked, .second: Tracked)

Nested: Type = (.pair: Pair)

Envelope: Type = (.result: Result, .sibling: Tracked)

main() -> (.status_code: Int32 = 0) := {
    counter :: Counter = Counter()
    {
        owner :: Nested = Nested(
            .pair = Pair(
                .first  = Tracked(.counter = $&counter, .id = 1)
                .second = Tracked(.counter = $&counter, .id = 3)
            )
        )
        sibling_id ::= &owner.pair.second.id
        owner.pair.first = make(.counter = $&counter, .id = 2)
        if counter.count != 1 { abort }
        if counter.order != 21 { abort }
        if sibling_id&!= 3 { abort }
    }
    if counter.count != 3 { abort }
    if counter.order != 2123 { abort }
    {
        owner :: Pair = Pair(
            .first  = Tracked(.counter = $&counter, .id = 4)
            .second = Tracked(.counter = $&counter, .id = 5)
        )
        moved ::= ~owner.first
        owner.first = Tracked(.counter = $&counter, .id = 6)
        if counter.count != 3 { abort }
    }
    if counter.count != 6 { abort }
    {
        owner :: Pair = Pair(
            .first  = Tracked(.counter = $&counter, .id = 7)
            .second = Tracked(.counter = $&counter, .id = 8)
        )
        owner = Pair(
            .first  = Tracked(.counter = $&counter, .id = 9)
            .second = Tracked(.counter = $&counter, .id = 0)
        )
        if counter.count != 8 { abort }
    }
    if counter.count != 10 { abort }
    {
        owner :: Envelope = Envelope(
            .result  = ..some Tracked(.counter = $&counter, .id = 1)
            .sibling = Tracked(.counter = $&counter, .id = 2)
        )
        owner.result = ..none
        if counter.count != 11 { abort }
        owner.result = ..some Tracked(.counter = $&counter, .id = 3)
        if counter.count != 11 { abort }
    }
    if counter.count != 13 { abort }
    status_code = 42
}
