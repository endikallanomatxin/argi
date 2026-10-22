Resource: Type = (.value: Int32)

Holder: Type = (.reference: $&Resource)

store(.holder: $&Holder, .other: $&Resource) -> () := {
    local :: Resource = (.value = 7)
    holder&= Holder(.reference = $&local)
    holder&.reference = other
}

main() -> (.status_code: Int32) := {
    owner :: Resource = (.value = 1)
    other :: Resource = (.value = 2)
    holder :: Holder = (.reference = $&owner)
    store(.holder = $&holder, .other = $&other)
    if holder.reference&.value != 2 { abort }
    status_code = 42
}
