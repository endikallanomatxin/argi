Resource : Type = (
    .value: Int32
)

Holder : Type = (
    .pointer: &Resource
)

replace_with_fresh(.self: $&Holder) -> () #sets_dependency_fresh(self, pointer) #raw_boundary := {}
deinit(.self: $&Resource) -> () #invalidates(self) := {}
read(.value: &Resource) -> () := {}

main() -> (.status_code: Int32) := {
    old :: Resource = (.value = 1)
    holder :: Holder = (.pointer = &old)

    replace_with_fresh(.self = $&holder)
    deinit(.self = $&old)
    read(.value = holder.pointer)
    status_code = 0
}
