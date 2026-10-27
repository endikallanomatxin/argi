Resource := (.value: Int32)

Holder := (.reference: $&Resource)

store := (.holder: $&Holder) -> () {
    local :: Resource = (.value = 7)
    holder&.reference = $&local
}

main := () -> (.status_code: Int32) {
    owner :: Resource = (.value = 1)
    holder :: Holder = (.reference = $&owner)
    store(.holder = $&holder)
    status_code = holder.reference&.value
}
