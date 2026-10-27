Counter := (.count: Int32 = 0)

Resource := (.counter: $&Counter, .id: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () { self&.counter&.count = self&.counter&.count + 1 }
)

borrow := (.owner: $&Resource) -> (.result: $&Resource) { result = owner }

main := () -> (.status_code: Int32 = 0) {
    counter :: Counter = Counter()
    owner :: Resource = Resource(.counter = $&counter, .id = 1)
    sibling := &owner.id
    target := borrow(.owner = $&owner)
    target&= Resource(.counter = $&counter, .id = 2)
    status_code = sibling&
}
