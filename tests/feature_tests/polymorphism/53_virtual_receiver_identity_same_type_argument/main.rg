Cell: Type = (.value: Int32)

implement Deinit#(Cell) (
    .deinit = (.self: $&Cell) -> () {

    }
)

Holder: Type = (.cell: Cell)

View#(.Participant: Type): Contract = (
    .get: (.other: &Holder, .self: &Participant) -> (.value: &Int32) where depends_on(value, self)
)

implement View#(Holder) (.get = _impl_get_Holder)

_impl_get_Holder := (.other: &Holder, .self: &Holder) -> (.value: &Int32)  {
    value = &self&.cell.value
}

read_view(.other: &Holder, .handle: &Virtual#(.contract: View)) -> (.value: &Int32) := {
    value = get(.other = other, .self = handle)
}

main() -> (.status_code: Int32 = 0) := {
    other :: Holder = (.cell = (.value = 2))
    holder :: Holder = (.cell = (.value = 1))
    handle ::= to_virtual#(.contract: View)(.value = &holder)
    value ::= read_view(.other = &other, .handle = &handle).value
    deinit(.self = $&other.cell)
    if value&!= 1 { status_code = 1 }
}
