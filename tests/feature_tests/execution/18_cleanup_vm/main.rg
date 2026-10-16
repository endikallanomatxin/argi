Counter: Type = (.count: Int32 = 0)

Tracked: Type = (.counter: $&Counter)

Pair: Type = (.first: Tracked, .second: Tracked)

implement Deinit#(Tracked) (
    .deinit = (.self: $&Tracked) -> () {
        self&.counter&.count = self&.counter&.count + 1
    }
)

leave_early(.counter: $&Counter) -> () := {
    owner ::= Tracked(.counter = counter)
    return
}

main() -> (.status_code: Int32 = 0) := {
    counter :: Counter = Counter()
    leave_early(.counter = $&counter)
    if counter.count != 1 { abort }
    while true {
        outer ::= Tracked(.counter = $&counter)
        {
            inner ::= Tracked(.counter = $&counter)
            break
        }
    }
    if counter.count != 3 { abort }
    index :: Int32 = 0
    while index < 3 {
        owner ::= Tracked(.counter = $&counter)
        index = index + 1
        continue
    }
    if counter.count != 6 { abort }
    {
        first ::= Tracked(.counter = $&counter)
        second ::= ~first
    }
    if counter.count != 7 { abort }
    {
        pair ::= Pair(
            .first = Tracked(.counter = $&counter), .second = Tracked(.counter = $&counter)
        )
        taken ::= ~pair.first
    }
    if counter.count != 9 { abort }
    {
        pair ::= Pair(
            .first = Tracked(.counter = $&counter), .second = Tracked(.counter = $&counter)
        )
        if counter.count == 9 {
            taken ::= ~pair.first
        }
        pair.first = Tracked(.counter = $&counter)
    }
    if counter.count != 12 { abort }
    status_code = 42
}
