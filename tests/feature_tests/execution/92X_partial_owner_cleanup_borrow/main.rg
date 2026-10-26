Counter := (.count: Int32)

Child := (.counter: $&Counter)

Parent := (.child: Child, .missing: Int32)

implement Deinit<Counter> (
    .deinit = (.self: $&Counter) -> () {}
)

implement Deinit<Child> (
    .deinit = (.self: $&Child) -> () {
        self&.counter&.count = self&.counter&.count + 1
    }
)

implement Deinit<Parent> (
    .deinit = (.self: $&Parent) -> () {}
)

main := () -> () {
    counter ::= Counter(.count = 0)
    parent :: Parent
    parent.child = Child(.counter = $&counter)
    deinit(.self = $&counter)
}
