Resource := (.value: Int32)

Holder := (.reference: $&Resource)

store := (.holder: $&Holder, .replace: Bool) -> () {
    local :: Resource = (.value = 7)
    if replace { holder&.reference = $&local }
}

main := () -> (.status_code: Int32) {
    owner :: Resource = (.value = 1)
    holder :: Holder = (.reference = $&owner)
    store(.holder = $&holder, .replace = true)
    status_code = holder.reference&.value
}
