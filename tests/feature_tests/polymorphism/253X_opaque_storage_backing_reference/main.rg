Source: Abstract = (
    get(.self: &Self, .storage: &Int32) -> (.reference: &Int32) where {
        from_storage(reference, storage)
    }
)

Cell: Type = ()

Cell implements Source

get(.self: &Cell, .storage: &Int32) -> (.reference: &Int32) := { reference = storage }

main() -> () := {
    cell ::= Cell()
    _ ::= to_virtual#(Source)(&cell)
}
