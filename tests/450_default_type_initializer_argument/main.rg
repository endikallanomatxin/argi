Counter : Type = (
    .value: Int32
)

init(.p: $&Counter) -> () := {
    p& = (
        .value = 7
    )
}

read_counter(.counter: Counter = Counter()) -> (.value: Int32) := {
    value = counter.value
}

main() -> (.status_code: Int32) := {
    status_code = read_counter()
}
