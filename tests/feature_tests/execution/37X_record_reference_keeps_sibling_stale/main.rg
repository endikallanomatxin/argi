Counter := (.count: Int32 = 0)

Resource := (.counter: $&Counter, .id: Int32)

Args := (.target: $&Resource, .sibling: &Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        self&.counter&.count = self&.counter&.count + 1
    }
)

main := () -> () {
    counter :: Counter = Counter()
    owner :: Resource = Resource(.counter = $&counter, .id = 1)
    args: Args = (.target = $&owner, .sibling = &owner.id)
    args.target&= Resource(.counter = $&counter, .id = 2)
    if args.sibling&!= 1 { abort }
}
