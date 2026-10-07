Mover: Abstract = (
    move(.self: &Self, .input: &Int32) -> (.value: &Int32) where transfers(value, input)
)

Cell: Type = (.value: Int32)

Cell implements Mover

move(.self: &Cell, .input: &Int32) -> (.value: &Int32) := {
    value = ~input
}

main() -> () := {}
