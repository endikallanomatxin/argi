Resource : Type = (
    .value: Int32
)

deinit(.self: $&Resource) -> () #invalidates(self) := {}
read(.value: &Resource) -> () := {}

main() -> (.status_code: Int32) := {
    resource :: Resource = (.value = 1)
    pointer := &resource
    deinit(.self = $&resource)
    read(.value = pointer)
    status_code = 0
}
