Resource : Type = (.value: Int32)
Holder : Type = (.pointer: &Resource)

replace_leaf(.self: $&Holder, .next: &Resource) -> () := {
    self&.pointer = next
}

replace_middle(.self: $&Holder, .next: &Resource) -> () := {
    replace_leaf(.self = self, .next = next)
}

replace_outer(.self: $&Holder, .next: &Resource) -> () := {
    replace_middle(.self = self, .next = next)
}

deinit(.self: $&Resource) -> () #invalidates(self) := {}
read(.value: &Resource) -> () := {}

main() -> (.status_code: Int32) := {
    first :: Resource = (.value = 1)
    second :: Resource = (.value = 2)
    holder :: Holder = (.pointer = &first)
    replace_outer(.self = $&holder, .next = &second)
    deinit(.self = $&second)
    read(.value = holder.pointer)
    status_code = 0
}
