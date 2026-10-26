Source<.Participant: Type>: Contract = (
    .item : Type

    .get : (.self: &Participant) -> (.value: item) where {}
)

Cell := (.value: Int32)

Other := (.value: Int32)

implement Source<Cell> (.item: Type = Int32, .get = _impl_get_Cell)

implement Source<Other> (.item: Type = Int32, .get = _impl_get_Other)

_impl_get_Cell := (.self: &Cell) -> (.value: Int32) {
    value = self&.value
}

_impl_get_Other := (.self: &Other) -> (.value: Int32) {
    value = self&.value + 1
}

read_source := (.source: &Virtual<Source<Int32>>) -> (.value: Int32) {
    value = get(source)
}

main := () -> (.status_code: Int32 = 0) {
    cell ::= Cell(42)
    other ::= Other(41)
    first ::= to_virtual<Source<Int32>>(&cell)
    second ::= to_virtual<Source<Int32>>(&other)

    if read_source(&first) != 42 or read_source(&second) != 42 {
        status_code = 1
    }
}
