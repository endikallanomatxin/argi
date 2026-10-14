View#(.Participant: Type): Contract = (
    .get: (.self: &Participant) -> (.value: &Int32) where depends_on(value, self)
)

Left: Type = (.value: Int32)

Right: Type = (.value: Int32)

implement View#(Left) (.get = _impl_get_Left)
implement View#(Right) (.get = _impl_get_Right)

_impl_get_Left := (.self: &Left) -> (.value: &Int32)  {
    value = &self&.value
}

_impl_get_Right := (.self: &Right) -> (.value: &Int32)  {
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
