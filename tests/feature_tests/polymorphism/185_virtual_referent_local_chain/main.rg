Forwarder#(.Participant: Type): Contract = (
    .forward: (.self: &Participant, .input: $&Int32) -> (.value: $&Int32)
    where refers_to(value, input)
)

Cell: Type = (.unused: Int32)

implement Forwarder#(Cell) (.forward = _impl_forward_Cell)

_impl_forward_Cell := (.self: &Cell, .input: $&Int32) -> (.value: $&Int32)  {
    first ::= input
    second ::= first
    value = second
}

forward_again(.handle: &Virtual#(Forwarder), .input: $&Int32) -> (.value: $&Int32) := {
    value = forward(handle, input)
}

main() -> (.status_code: Int32 = 0) := {
    cell ::= Cell(0)
    input :: Int32 = 41
    handle ::= to_virtual#(Forwarder)(&cell)
    reference ::= forward_again(&handle, $&input)
    reference&= 42

    if input != 42 {
        status_code = 1
    }
}
