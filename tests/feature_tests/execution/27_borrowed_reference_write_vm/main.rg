Counter := (.count: Int32 = 0)

Resource := (.counter: $&Counter)

implement Deinit<Resource> (
    .deinit = (.self: $&Resource) -> () {
        self&.counter&.count = self&.counter&.count + 1
    }
)

Borrow := (.resource: &Resource, .number: Int32)

replace := (.target: $&Borrow, .resource: &Resource) -> () {
    target&= Borrow(.resource = resource, .number = 42)
}

main := () -> (.status_code: Int32 = 0) {
    counter :: Counter = Counter()
    {
        owner :: Resource = Resource(.counter = $&counter)
        borrowed :: Borrow = Borrow(.resource = &owner, .number = 0)
        replace(.target = $&borrowed, .resource = &owner)
        if counter.count != 0 { abort }
        if borrowed.number != 42 { abort }
    }
    if counter.count != 1 { abort }
    status_code = 42
}
