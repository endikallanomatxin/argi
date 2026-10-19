Counter: Type = (.count: Int32)

Resource: Type = (.counter: $&Counter)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        self&.counter&.count = self&.counter&.count + 1
    }
)

main := () -> (.status_code: Int32 = 0) {
    counter :: Counter = (.count = 0)
    {
        resource :: Resource
        resource.counter = $&counter
    }
    if counter.count != 1 { abort }
    status_code = 42
}
