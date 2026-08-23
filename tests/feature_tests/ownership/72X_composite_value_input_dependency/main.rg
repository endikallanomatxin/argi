Resource : Type = (
    .value: Int32
)

Holder : Type = (
    .pointer: &Resource
)

deinit(.self: $$&Resource) -> () #invalidates(self) := {}

get_value(.holder: Holder) -> (.result: &Resource) := {
    result = holder.pointer
}

read(.value: &Resource) -> () := {}

main() -> (.status_code: Int32) := {
    resource :: Resource = (.value = 1)
    holder :: Holder = (.pointer = &resource)
    returned := get_value(.holder = holder).result
    deinit(.self = $$&resource)
    read(.value = returned)
    status_code = 0
}
