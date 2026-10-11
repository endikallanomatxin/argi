Forwarder: Abstract = (
    forward(.self: &Self, .input: Owned) -> (.value: Owned) where transfers(value, input)
)

Cell: Type = (.unused: Int32)

Cell implements Forwarder

Owned: Type = (.value: Int32)

Owned deinit(.self: $&Owned) -> () := { drops = drops + 1 }

drops :: Int32 = 0

forward(.self: &Cell, .input: Owned) -> (.value: Owned) := {
    fresh ::= Owned(input.value)
    value = ~fresh
}

main() -> (.status_code: Int32 = 0) := {
    cell ::= Cell(0)
    forwarder ::= to_virtual#(Forwarder)(&cell)
    value ::= forward(&forwarder, Owned(42))
    if value.value != 42 { status_code = 1 }
    deinit($&value)
    if drops != 1 { status_code = 1 }
}
