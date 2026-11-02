Counter := (.count: Int32)

Resource := (.counter: $&Counter)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        self&.counter&.count = self&.counter&.count + 1
    }
)

probe := () -> (.result: Int32) {
    counter :: Counter = (.count = 0)
    {
        resource :: Resource
        resource.counter = $&counter
    }
    if counter.count != 1 { abort }
    result = 42
}

main := () -> (.status_code: Int32) {
    if #run () -> (.value: Int32) { value = probe() } != 42 { abort }
    status_code = probe()
}
