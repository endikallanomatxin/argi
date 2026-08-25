Resource : Type = (
    .value: Int32
)

Holder : Type = (
    .pointer: &Resource
)

deinit(.self: $&Resource) -> () #invalidates(self) := {}

get(.holder: &Holder) -> (.result: &Resource) := {
    result = holder&.pointer
}

read(.value: &Resource) -> () := {}

main() -> (.status_code: Int32) := {
    resource :: Resource = (.value = 1)
    holder :: Holder = (.pointer = &resource)
    pointer := get(.holder = &holder).result
    deinit(.self = $&resource)
    read(.value = pointer)
    status_code = 0
}
