Resource : Type = (
    .value: Int32
)

deinit(.self: $$&Resource) -> () := {}
read(.value: &Resource) -> () := {}

main() -> (.status_code: Int32) := {
    resource :: Resource = (.value = 1)
    pointer := &resource
    condition := true
    if condition {
        deinit(.self = $$&resource)
    } else {
        read(.value = pointer)
    }
    status_code = 0
}
