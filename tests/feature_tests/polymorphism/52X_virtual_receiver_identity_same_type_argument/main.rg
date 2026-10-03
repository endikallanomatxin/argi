Cell : Type = (.value: Int32)
Cell deinit(.self: $&Cell) -> () := {}
Holder : Type = (.cell: Cell)
View : Abstract = (get(.other: &Holder, .self: &Self) -> (.value: &Int32))
Holder implements View
get(.other: &Holder, .self: &Holder) -> (.value: &Int32) := {
    value = &self&.cell.value
}
read_view(.other: &Holder, .handle: &Virtual#(.abstract: View)) -> (.value: &Int32) := {
    value = get(.other = other, .self = handle)
}
main() -> (.status_code: Int32 = 0) := {
    other :: Holder = (.cell = (.value = 2))
    holder :: Holder = (.cell = (.value = 1))
    handle ::= to_virtual#(.abstract: View)(.value = &holder)
    deinit(.self = $&holder.cell)
    value ::= read_view(.other = &other, .handle = &handle).value
    observed ::= value&
    abort
}
