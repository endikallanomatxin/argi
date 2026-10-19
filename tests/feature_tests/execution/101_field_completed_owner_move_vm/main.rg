Counter: Type = (.count: Int32)

Resource: Type = (.counter: $&Counter, .value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        self&.counter&.count = self&.counter&.count + 1
    }
)

probe := () -> (.result: Int32 = 0) {
    counter :: Counter = (.count = 0)
    {
        resource :: Resource
        resource.counter = $&counter
        resource.value = 42
        complete ::= ~resource
        result = complete.value
    }
    if counter.count != 1 { abort }
}

main := () -> (.status_code: Int32) {
    if #run probe() != 42 { abort }
    status_code = probe()
}
