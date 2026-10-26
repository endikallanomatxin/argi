View<.Participant: Type>: Contract = (
    .get : (.self: &Participant) -> (.result: RefResult) where depends_on(result, self)
)

RefResult := (.reference: &Int32)

Cell := (.value: Int32)

implement Deinit<Cell> (
    .deinit = (.self: $&Cell) -> () {

    }
)

Holder := (.cell: Cell)

Other := (.cell: Cell)

implement View<Holder> (.get = _impl_get_Holder)

implement View<Other> (.get = _impl_get_Other)

_impl_get_Holder := (.self: &Holder) -> (.result: RefResult) {
    result = (.reference = &self&.cell.value)
}

_impl_get_Other := (.self: &Other) -> (.result: RefResult) {
    result = (.reference = &self&.cell.value)
}

register_other := (.value: $&Other) -> () {
    unused ::= to_virtual<.contract: View>(.value = value)
}

main := () -> (.status_code: Int32) {
    other :: Other = (.cell = (.value = 2))
    register_other(.value = $&other)
    holder :: Holder = (.cell = (.value = 1))
    virtual ::= to_virtual<.contract: View>(.value = $&holder)
    deinit(.self = $&holder.cell)
    result ::= get(.self = &virtual)
    status_code = result.reference&
}
