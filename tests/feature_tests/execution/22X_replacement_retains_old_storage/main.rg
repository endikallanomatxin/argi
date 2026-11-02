Counter := (.count: Int32 = 0)

Owner := (.counter: $&Counter, .value: Int32, .saved: &Int32)

implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () {
        self&.counter&.count = self&.counter&.count + 1
    }
)

main := () -> () {
    counter :: Counter = Counter()
    external ::= 0
    owner :: Owner = Owner(.counter = $&counter, .value = 1, .saved = &external)
    owner = Owner(.counter = $&counter, .value = 2, .saved = &owner.value)
    observed ::= owner.saved&
}
