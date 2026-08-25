Resource : Type = (
    .value: Int32
)

Holder : Type = (
    .pointer: &Resource
)

deinit(.self: $&Resource) -> () #invalidates(self) := {}

replace(.self: $&Holder, .next: &Resource) -> () := {
    self&.pointer = next
}

read(.value: &Resource) -> () := {}

main() -> (.status_code: Int32) := {
    first :: Resource = (.value = 1)
    second :: Resource = (.value = 2)
    holder :: Holder = (.pointer = &first)

    replace(.self = $&holder, .next = &second)
    deinit(.self = $&second)
    read(.value = holder.pointer)
    status_code = 0
}
