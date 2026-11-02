Counter := (.count: Int32 = 0)

Resource := (.value: Int32, .counter: $&Counter)

Holder := (.item: Resource)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () { self&.counter&.count = self&.counter&.count + 1 }
)

read := (.value: &Resource) -> (.result: Int32) { result = value&.value }

consume := (.value: $&Resource) -> () { deinit(.self = value) }

observe := (.self: $&Holder, .other: &Resource, .counter: $&Counter) -> (.result: Int32) {
    index :: Int32 = 0
    while index < 2 {
        result = read(.value = other)
        consume(.value = $&self&.item)
        self&.item = Resource(.value = 42, .counter = counter)
        index = index + 1
    }
}

forward := (.self: $&Holder, .other: &Resource, .counter: $&Counter) -> (.result: Int32) {
    result = observe(.self = self, .other = other, .counter = counter)
}

main := () -> (.status_code: Int32) {
    counter :: Counter = Counter()
    holder :: Holder = Holder(.item = Resource(.value = 42, .counter = $&counter))
    status_code = forward(.self = $&holder, .other = &holder.item, .counter = $&counter)
}
