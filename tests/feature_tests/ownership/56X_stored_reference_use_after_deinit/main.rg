Resource : Type = (
    .value: Int32
)

Holder : Type = (
    .pointer: &Resource
    .tag: Int32
)

deinit(.self: $&Resource) -> () #invalidates(self) := {}
read(.value: &Resource) -> () := {}

main() -> (.status_code: Int32) := {
    resource :: Resource = (.value = 1)
    holder :: Holder = (.pointer = &resource, .tag = 7)
    deinit(.self = $&resource)
    read(.value = holder.pointer)
    status_code = 0
}
