Forwarder: Abstract = (
    forward(.self: &Self, .input: &Int32) -> (.value: $&Int32)
    where refers_to(value, input)
)

Cell: Type = (.unused: Int32)

Cell implements Forwarder

global :: Int32 = 0

forward(.self: &Cell, .input: &Int32) -> (.value: $&Int32) := {
    value = $&global
}

main() -> () := {
    cell ::= Cell(0)
    handle ::= to_virtual#(Forwarder)(&cell)
}
