Counter := (.drops: Int32 = 0, .indices: Int32 = 0)

Resource := (.counter: $&Counter, .value: Int32)

Empty: Type = ()

empty_drops :: Int32 = 0

implement Deinit<Empty> (
    .deinit = (.self: $&Empty) -> () { empty_drops = empty_drops + 1 }
)

implement Deinit<Resource> (
    .deinit = (.self: $&Resource) -> () {
        self&.counter&.drops = self&.counter&.drops + 1
    }
)

index := (.counter: $&Counter) -> (.result: UIntNative) {
    counter&.indices = counter&.indices + 1
    result = 0
}

replacement := (.selection: $&UIntNative, .counter: $&Counter) -> (.result: Resource) {
    selection&= 1
    result = Resource(.counter = counter, .value = 42)
}

replacement_drops := () -> (.result: Int32) {
    counter :: Counter = Counter()
    {
        resources :: [1]Resource = (Resource(.counter = $&counter, .value = 1))
        resources[0] = Resource(.counter = $&counter, .value = 2)
    }
    result = counter.drops
}

main := () -> (.status_code: Int32) {
    counter :: Counter = Counter()
    {
        resources :: [2]Resource = (
            Resource(.counter = $&counter, .value = 1),
            Resource(.counter = $&counter, .value = 2)
        )
        resources[index(.counter = $&counter)] = Resource(.counter = $&counter, .value = 42)
        if counter.drops != 1 { abort }
        if counter.indices != 1 { abort }
        if resources[0].value != 42 { abort }
        if resources[1].value != 2 { abort }
    }
    if counter.drops != 3 { abort }
    {
        resources :: [2]Resource = (
            Resource(.counter = $&counter, .value = 1),
            Resource(.counter = $&counter, .value = 2)
        )
        selection :: UIntNative = 0
        resources[selection] = replacement(.selection = $&selection, .counter = $&counter)
        if selection != 1 { abort }
        if counter.drops != 4 { abort }
        if resources[0].value != 42 { abort }
        if resources[1].value != 2 { abort }
    }
    if counter.drops != 6 { abort }
    {
        resources :: [2]Resource = (
            Resource(.counter = $&counter, .value = 1),
            Resource(.counter = $&counter, .value = 2)
        )
        sibling ::= &resources[1]
        deinit(.self = $&resources[0])
        resources[0] = Resource(.counter = $&counter, .value = 42)
        if counter.drops != 7 { abort }
        if sibling&.value != 2 { abort }
        if resources[0].value != 42 { abort }
    }
    if counter.drops != 9 { abort }
    {
        values :: [2]Empty = (
            (),
            ()
        )
        values[0] = ()
        if empty_drops != 1 { abort }
    }
    if empty_drops != 3 { abort }
    if #run () -> (.count: Int32) { count = replacement_drops() } != 2 { abort }
    status_code = 42
}
