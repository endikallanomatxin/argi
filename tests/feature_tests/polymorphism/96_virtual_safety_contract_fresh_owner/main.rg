Factory<.Participant: Type>: Contract = (
    .make : (.self: &Participant) -> (.value: Owned) where owns(value)
)

Cell := (.unused: Int32)

implement Factory<Cell> (.make = _impl_make_Cell)

Owned := (.value: Int32)

implement Deinit<Owned> (
    .deinit = (.self: $&Owned) -> () {
        drops = drops + 1
    }
)

drops :: Int32 = 0

_impl_make_Cell := (.self: &Cell) -> (.value: Owned) {
    value = Owned(42)
}

create := (.factory: &Virtual<Factory>) -> (.value: Owned) {
    value = make(factory)
}

main := () -> (.status_code: Int32 = 0) {
    cell ::= Cell(0)
    factory ::= to_virtual<Factory>(&cell)
    value ::= create(&factory)
    if value.value != 42 { status_code = 1 }
    deinit($&value)
    if drops != 1 { status_code = 1 }
}
