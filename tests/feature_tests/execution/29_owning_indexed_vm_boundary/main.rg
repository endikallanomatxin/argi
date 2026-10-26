Counter := (.count: Int32 = 0)

Resource := (.counter: $&Counter)

implement Deinit<Resource> (
    .deinit = (.self: $&Resource) -> () {
        self&.counter&.count = self&.counter&.count + 1
    }
)

main := () -> () {
    counter :: Counter = Counter()
    owners :: [2]Resource = (
        Resource(.counter = $&counter),
        Resource(.counter = $&counter)
    )
    owners[0] = Resource(.counter = $&counter)
}
