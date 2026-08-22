Resource : Type = (
    .value: Int32
)

transition(.self: $$&Resource) -> () := {}
read(.value: &Resource) -> () := {}

main() -> (.status_code: Int32) := {
    resource :: Resource = (.value = 1)
    pointer := &resource
    transition(.self = $$&resource)
    read(.value = pointer)
    status_code = 0
}
