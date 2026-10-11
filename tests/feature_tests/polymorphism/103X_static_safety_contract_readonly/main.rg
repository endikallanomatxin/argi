Editor: Abstract = (
    edit(.self: &Self, .target: &Int32) -> () where invalidates(target)
)

Cell: Type = (.value: Int32)

Cell implements Editor

edit(.self: &Cell, .target: &Int32) -> () := {}

main() -> () := {}
