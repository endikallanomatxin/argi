View : Abstract = (
    get(.self: &Self) -> (.value: &Int32)
)

Cell : Type = (.value: Int32)
Holder : Type = (.cell: Cell)
Other : Type = (.cell: Cell)
Holder implements View
Other implements View

get(.self: &Holder) -> (.value: &Int32) := {
    value = &self&.cell.value
}

get(.self: &Other) -> (.value: &Int32) := {
    value = &self&.cell.value
}

register_other(.value: $&Other) -> () := {
    unused ::= to_virtual#(.abstract: View)(.value = value)
}

main() -> (.status_code: Int32 = 0) := {
    other :: Other = (.cell = (.value = 2))
    register_other(.value = $&other)
    holder :: Holder = (.cell = (.value = 1))
    virtual ::= to_virtual#(.abstract: View)(.value = $&holder)
    value ::= get(.self = &virtual)
    if value& != 1 { status_code = 1 }
}
