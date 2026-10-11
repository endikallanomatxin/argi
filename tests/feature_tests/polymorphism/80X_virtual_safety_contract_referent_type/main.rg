Forwarder: Abstract = (
    forward(.self: &Self, .input: $&Int32) -> (.value: &UInt8)
    where refers_to(value, input)
)

Cell: Type = (.unused: Int32)

Cell implements Forwarder

global :: UInt8 = 0

forward(.self: &Cell, .input: $&Int32) -> (.value: &UInt8) := {
    value = &global
}

main() -> () := {
    cell ::= Cell(0)
    handle ::= to_virtual#(Forwarder)(&cell)
}
