Counter := (
    .value: Int32
)

implement Init#(Counter, ()) (
    .Result: Type = Counter
    .init = (.args: ()) -> (.result: Result) {
        result = (
            .value = 7
        )
    }
)

read_counter := (.counter: Counter = Counter()) -> (.value: Int32)  {
    value = counter.value
}

main := () -> (.status_code: Int32)  {
    status_code = read_counter()
}
