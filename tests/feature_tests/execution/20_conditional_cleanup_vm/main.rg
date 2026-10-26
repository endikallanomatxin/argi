Counter := (.count: Int32 = 0)

Resource := (.counter: $&Counter)

Manager: Type = ()

implement Deinit<Resource> (
    .deinit = (.self: $&Resource) -> () {
        self&.counter&.count = self&.counter&.count + 1
    }
)

release_resource := (.self: &Manager, .resource: $&Resource, .consume: Bool) -> (
    .result : ?Int32
) {
    if consume {
        deinit(.self = resource)
        result = ..some(.value = 42)
        return
    }
    result = ..none
}

main := () -> (.status_code: Int32 = 0) {
    counter :: Counter = Counter()
    manager ::= Manager()
    {
        resource ::= Resource(.counter = $&counter)
        release_resource(.self = &manager, .resource = $&resource, .consume = false)
    }
    if counter.count != 1 { abort }
    {
        resource ::= Resource(.counter = $&counter)
        release_resource(.self = &manager, .resource = $&resource, .consume = true)
    }
    if counter.count != 2 { abort }
    status_code = 42
}
