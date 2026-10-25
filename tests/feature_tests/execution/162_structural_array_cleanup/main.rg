Counter: Type = (.count: Int32 = 0)

Resource: Type = (.counter: $&Counter)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () { self&.counter&.count = self&.counter&.count + 1 }
)

count_array_drops() -> (.result: Int32) := {
    counter :: Counter = Counter()
    {
        resources :: [2]Resource = (
            Resource(.counter = $&counter),
            Resource(.counter = $&counter)
        )
    }
    result = counter.count
}

drop_pair(.resources: [2]Resource) -> () := { owned ::= ~resources }

main() -> (.status_code: Int32) := {
    counter :: Counter = Counter()
    {
        resources :: [2]Resource = (
            Resource(.counter = $&counter),
            Resource(.counter = $&counter)
        )
    }
    if counter.count != 2 { abort }
    {
        resources :: [2]Resource = (
            Resource(.counter = $&counter),
            Resource(.counter = $&counter)
        )
        deinit(.self = $&resources[0])
    }
    if counter.count != 4 { abort }
    {
        resources :: [2]Resource = (
            Resource(.counter = $&counter),
            Resource(.counter = $&counter)
        )
        moved ::= ~resources[0]
    }
    if counter.count != 6 { abort }
    {
        empty :: [0]Resource = ()
    }
    if counter.count != 6 { abort }
    {
        nested :: [2][2]Resource = (
            (Resource(.counter = $&counter), Resource(.counter = $&counter)),
            (Resource(.counter = $&counter), Resource(.counter = $&counter))
        )
    }
    if counter.count != 10 { abort }
    {
        resources :: [2]Resource = (
            Resource(.counter = $&counter),
            Resource(.counter = $&counter)
        )
        drop_pair(.resources = ~resources)
    }
    if counter.count != 12 { abort }
    if #run () -> (.value: Int32) { value = count_array_drops() } != 2 { abort }
    #if count_array_drops() == 2 { status_code = 42 } else { abort }
}
