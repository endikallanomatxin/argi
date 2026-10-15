Choose#(.Participant: Type): Contract = (
    .choose: (.self: &Participant, .other: &Int32) -> (.value: &Int32) where depends_on(value, self, other)
)

FromSelf: Type = (.value: Int32)

FromOther: Type = (.value: Int32)

implement Choose#(FromSelf) (.choose = _impl_choose_FromSelf)
implement Choose#(FromOther) (.choose = _impl_choose_FromOther)

_impl_choose_FromSelf := (.self: &FromSelf, .other: &Int32) -> (.value: &Int32)  {
    value = &self&.value
}

_impl_choose_FromOther := (.self: &FromOther, .other: &Int32) -> (.value: &Int32)  {
    value = other
}

register_other(.value: $&FromOther) -> () := {
    unused ::= to_virtual#(.contract: Choose)(.value = value)
}

escape(.self: $&FromSelf) -> (.value: &Int32) := {
    local :: Int32 = 2
    virtual ::= to_virtual#(.contract: Choose)(.value = self)
    value = choose(.self = &virtual, .other = &local)
}

main() -> (.status_code: Int32) := {
    other :: FromOther = (.value = 0)
    register_other(.value = $&other)
    source :: FromSelf = (.value = 1)
    escaped ::= escape(.self = $&source)
    status_code = escaped&
}
