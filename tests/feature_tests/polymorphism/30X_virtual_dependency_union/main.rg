Choose : Abstract = (
    choose(.self: &Self, .other: &Int32) -> (.value: &Int32)
)

FromSelf : Type = (.value: Int32)
FromOther : Type = (.value: Int32)
FromSelf implements Choose
FromOther implements Choose

choose(.self: &FromSelf, .other: &Int32) -> (.value: &Int32) := {
    value = &self&.value
}

choose(.self: &FromOther, .other: &Int32) -> (.value: &Int32) := {
    value = other
}

register_other(.value: $&FromOther) -> () := {
    unused ::= to_virtual#(.abstract: Choose)(.value = value)
}

escape(.self: $&FromSelf) -> (.value: &Int32) := {
    local :: Int32 = 2
    virtual ::= to_virtual#(.abstract: Choose)(.value = self)
    value = choose(.self = &virtual, .other = &local)
}

main() -> (.status_code: Int32) := {
    other :: FromOther = (.value = 0)
    register_other(.value = $&other)
    source :: FromSelf = (.value = 1)
    escaped ::= escape(.self = $&source)
    status_code = escaped&
}
