Counter : Type = (
    .value: Int32
)

Counter init() -> (.result: Counter) := {
    result = (
        .value = 7
    )
}

read_counter(.counter: Counter = Counter()) -> (.value: Int32) := {
    value = counter.value
}

main() -> (.status_code: Int32) := {
    status_code = read_counter()
}
