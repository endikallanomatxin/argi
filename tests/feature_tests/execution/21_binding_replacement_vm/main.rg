Counter := (.count: Int32 = 0, .order: Int32 = 0)

Tracked := (.counter: $&Counter, .id: Int32)

Result: Type = (..some Tracked, ..none)

implement Deinit<Tracked> (
    .deinit = (.self: $&Tracked) -> () {
        self&.counter&.count = self&.counter&.count + 1
        self&.counter&.order = self&.counter&.order * 10 + self&.id
    }
)

make := (.counter: $&Counter, .id: Int32) -> (.result: Tracked) {
    index :: Int32 = 0
    while index < 1 { index = index + 1 }
    counter&.order = counter&.order * 10 + id
    result = Tracked(.counter = counter, .id = id)
}

make_twice := (.counter: $&Counter) -> (.result: Tracked) {
    result = Tracked(.counter = counter, .id = 4)
    result = Tracked(.counter = counter, .id = 5)
}

main := () -> (.status_code: Int32 = 0) {
    counter :: Counter = Counter()
    {
        owner :: Tracked = Tracked(.counter = $&counter, .id = 1)
        owner = make(.counter = $&counter, .id = 2)
        if counter.count != 1 { abort }
        if counter.order != 21 { abort }
    }
    if counter.count != 2 { abort }
    if counter.order != 212 { abort }
    {
        value :: Result = ..some Tracked(.counter = $&counter, .id = 3)
        value = ..none
        if counter.count != 3 { abort }
    }
    if counter.count != 3 { abort }
    {
        owner ::= make_twice(.counter = $&counter)
        if counter.count != 4 { abort }
    }
    if counter.count != 5 { abort }
    if counter.order != 212345 { abort }
    status_code = 42
}
