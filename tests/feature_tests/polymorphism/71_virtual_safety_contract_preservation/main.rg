Counter#(.Participant: Type): Contract = (
    .increment: (.self: $&Participant) -> () where {}
    .count: (.self: &Participant) -> (.value: Int32) where {}
)

Cell: Type = (.value: Int32)

implement Counter#(Cell) (.increment = _impl_increment_Cell, .count = _impl_count_Cell)

_impl_increment_Cell := (.self: $&Cell) -> ()  {
    self&.value = self&.value + 1
}

_impl_count_Cell := (.self: &Cell) -> (.value: Int32)  {
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
