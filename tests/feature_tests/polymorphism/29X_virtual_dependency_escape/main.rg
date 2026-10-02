View : Abstract = (
    get(.self: &Self) -> (.value: &Int32)
)

Left : Type = (.value: Int32)
Right : Type = (.value: Int32)
Left implements View
Right implements View

get(.self: &Left) -> (.value: &Int32) := {
    value = &self&.value
}

get(.self: &Right) -> (.value: &Int32) := {
    value = &self&.value
}

register_right(.value: $&Right) -> () := {
    unused ::= to_virtual#(.abstract: View)(.value = value)
}

escape() -> (.value: &Int32) := {
    left :: Left = (.value = 1)
    virtual ::= to_virtual#(.abstract: View)(.value = $&left)
    value = get(.self = &virtual)
}

main() -> (.status_code: Int32) := {
    right :: Right = (.value = 2)
    register_right(.value = $&right)
    escaped ::= escape()
    status_code = escaped&
}
