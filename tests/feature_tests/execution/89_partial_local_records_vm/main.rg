Pair: Type = (.first: Int32, .second: (.value: Int32))

set_number := (.destination: $&Int32, .value: Int32) -> () {
    destination&= value
}

exercise := () -> (.result: Int32 = 0) {
    index :: Int32 = 0
    while index < 2 {
        pair :: Pair
        pair.first = 40
        set_number(.destination = $&pair.second.value, .value = [pair.first + 2])
        result = pair.second.value
        index = index + 1
    }
}

main := () -> (.status_code: Int32 = 0) {
    compiled ::= #run exercise()
    if compiled != 42 { abort }
    if [#run whole_owner()] != 42 { abort }
    if whole_owner() != 42 { abort }
    status_code = exercise()
}

Counter: Type = (.count: Int32)

Resource: Type = (.counter: $&Counter)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        self&.counter&.count = self&.counter&.count + 1
    }
)

whole_owner := () -> (.result: Int32 = 0) {
    counter :: Counter = (.count = 0)
    {
        resource :: Resource
        resource = (.counter = $&counter)
    }
    if counter.count != 1 { abort }
    result = 42
}
