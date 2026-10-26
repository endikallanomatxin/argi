Counter := (.count: Int32 = 0)

Tracked := (.counter: $&Counter)

Result: Type = (..some(.owner: Tracked), ..none)

implement Deinit<Tracked> (
    .deinit = (.self: $&Tracked) -> () {
        self&.counter&.count = self&.counter&.count + 1
    }
)

main := () -> (.status_code: Int32 = 0) {
    counter :: Counter = Counter()
    {
        value :: Result = ..none
    }
    if counter.count != 0 { abort }
    {
        value :: Result = ..some(.owner = Tracked(.counter = $&counter))
    }
    if counter.count != 1 { abort }
    {
        value :: Result = ..some(.owner = Tracked(.counter = $&counter))
        match value {
            ..some ~payload { taken ::= ~payload.owner }
            ..none { abort }
        }
    }
    if counter.count != 2 { abort }
    {
        owner ::= Tracked(.counter = $&counter)
        deinit(.self = $&owner)
    }
    if counter.count != 3 { abort }
    {
        value :: Result = ..some(.owner = Tracked(.counter = $&counter))
        value = ..none
    }
    if counter.count != 4 { abort }
    status_code = 42
}
