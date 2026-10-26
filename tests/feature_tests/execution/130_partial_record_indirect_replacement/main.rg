Counter := (.count: Int32 = 0)

Resource := (.counter: $&Counter)

implement Deinit<Resource> (
    .deinit = (.self: $&Resource) -> () { self&.counter&.count = self&.counter&.count + 1 }
)

Wrapper := (.item: Resource, .whole: $&Counter)

implement Deinit<Wrapper> (
    .deinit = (.self: $&Wrapper) -> () {
        self&.whole&.count = self&.whole&.count + 1
        deinit(.self = $&self&.item)
    }
)

replace_incomplete := (.owner: $&Wrapper, .counter: $&Counter, .whole: $&Counter) -> () {
    deinit(.self = $&owner&.item)
    owner&= Wrapper(.item = Resource(.counter = counter), .whole = whole)
}

main := () -> (.status_code: Int32 = 0) {
    counter :: Counter = Counter()
    whole :: Counter = Counter()
    {
        owner :: Wrapper = Wrapper(.item = Resource(.counter = $&counter), .whole = $&whole)
        replace_incomplete(.owner = $&owner, .counter = $&counter, .whole = $&whole)
    }
    if whole.count != 1 or counter.count != 2 { abort }
    status_code = 42
}
