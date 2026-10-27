Counter := (.count: Int32)

Child := (.counter: $&Counter)

implement Deinit#(Counter) (
    .deinit = (.self: $&Counter) -> () {}
)

implement Deinit#(Child) (
    .deinit = (.self: $&Child) -> () {
        self&.counter&.count = self&.counter&.count + 1
    }
)

main := () -> () {
    counter ::= Counter(.count = 0)
    child :: Child
    child.counter = $&counter
    deinit(.self = $&counter)
}
