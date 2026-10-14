View#(.Participant: Type): Contract = (
    .get: (.self: &Participant) -> (.value: &Int32) where depends_on(value, self)
)

Cell: Type = (.value: Int32)

implement Deinit#(Cell) (
    .deinit = (.self: $&Cell) -> () {

    }
)

Holder: Type = (.cell: Cell)

Other: Type = (.cell: Cell)

implement View#(Holder) (.get = _impl_get_Holder)
implement View#(Other) (.get = _impl_get_Other)

_impl_get_Holder := (.self: &Holder) -> (.value: &Int32)  {
    value = &self&.cell.value
}

_impl_get_Other := (.self: &Other) -> (.value: &Int32)  {
    value = &self&.cell.value
}

register_other(.value: $&Other) -> () := {
    unused ::= to_virtual#(.contract: View)(.value = value)
}

main() -> (.status_code: Int32) := {
    other :: Other = (.cell = (.value = 2))
    register_other(.value = $&other)
    holder :: Holder = (.cell = (.value = 1))
    virtual ::= to_virtual#(.contract: View)(.value = $&holder)
    deinit(.self = $&holder.cell)
    value ::= get(.self = &virtual)
    status_code = value&
}
