Counter: Abstract = (
    increment(.self: $&Self) -> () where {}
    count(.self: &Self) -> (.value: Int32) where {}
)

Cell: Type = (.value: Int32)

Cell implements Counter

increment(.self: $&Cell) -> () := {
    self&.value = self&.value + 1
}

count(.self: &Cell) -> (.value: Int32) := {
    value = self&.value
}

read_counter(.counter: $&Virtual#(Counter)) -> (.value: Int32) := {
    increment(counter)
    value = count(counter)
}

main() -> (.status_code: Int32 = 0) := {
    cell ::= Cell(41)
    counter ::= to_virtual#(Counter)($&cell)

    if read_counter($&counter) != 42 {
        status_code = 1
    }
}
