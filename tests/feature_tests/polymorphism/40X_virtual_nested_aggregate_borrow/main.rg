View : Abstract = (
    get(.self: &Self) -> (.result: RefResult)
)

RefResult : Type = (.reference: &Int32)
Cell : Type = (.value: Int32)
deinit(.self: $&Cell) -> () := {}
Holder : Type = (.cell: Cell)
Other : Type = (.cell: Cell)
Holder implements View
Other implements View

get(.self: &Holder) -> (.result: RefResult) := {
    result = (.reference = &self&.cell.value)
}

get(.self: &Other) -> (.result: RefResult) := {
    result = (.reference = &self&.cell.value)
}

register_other(.value: $&Other) -> () := {
    unused ::= to_virtual#(.abstract: View)(.value = value)
}

main() -> (.status_code: Int32) := {
    other :: Other = (.cell = (.value = 2))
    register_other(.value = $&other)
    holder :: Holder = (.cell = (.value = 1))
    virtual ::= to_virtual#(.abstract: View)(.value = $&holder)
    deinit(.self = $&holder.cell)
    result ::= get(.self = &virtual)
    status_code = result.reference&
}
