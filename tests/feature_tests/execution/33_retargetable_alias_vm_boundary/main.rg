Counter: Type = (.count: Int32 = 0)

Resource: Type = (.counter: $&Counter, .id: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        self&.counter&.count = self&.counter&.count + 1
    }
)

main() -> () := {
    counter :: Counter = Counter()
    {
        first :: Resource = Resource(.counter = $&counter, .id = 1)
        second :: Resource = Resource(.counter = $&counter, .id = 2)
        target :: $&Resource = $&first
        target = $&second
        target&= Resource(.counter = $&counter, .id = 3)
        if counter.count != 1 { abort }
    }
    if counter.count != 3 { abort }
}
