Resource : Type = (
    .value: Int32
)

Holder : Type = (
    .pointer: &Resource
    .tag: Int32
)

deinit(.self: $$&Resource) -> () := {}

main() -> (.status_code: Int32) := {
    resource :: Resource = (.value = 1)
    holder :: Holder = (.pointer = &resource, .tag = 7)
    deinit(.self = $$&resource)
    status_code = holder.tag - 7
}
