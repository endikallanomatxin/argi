Resource : Type = (
    .value: Int32
)

Holder : Type = (
    .pointer: &Resource
)

replace(.self: $&Holder, .next: &Resource) -> () := {
    self&.pointer = next
}

main() -> (.status_code: Int32) := {
    first :: Resource = (.value = 1)
    second :: Resource = (.value = 2)
    holder :: Holder = (.pointer = &first)
    replace(.self = $&holder, .next = &second)
    status_code = 0
}
