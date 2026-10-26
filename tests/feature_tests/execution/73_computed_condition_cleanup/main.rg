Counter := (.count: Int32 = 0)

Resource := (.counter: $&Counter)

implement Deinit<Resource> (
    .deinit = (.self: $&Resource) -> () {
        self&.counter&.count = self&.counter&.count + 1
    }
)

main := () -> (.status_code: Int32 = 0) {
    counter :: Counter = Counter()
    {
        #if true {
            owner :: Resource = Resource(.counter = $&counter)
        } #else {
            unavailable_discarded_cleanup()
        }
        if counter.count != 0 { abort }
    }
    if counter.count != 1 { abort }
    status_code = 42
}
