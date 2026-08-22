Resource : Type = (
    .value: Int32
)

transition(.self: $$&Resource) -> () := {
    self&.value = 2
}
read(.value: &Int32) -> () := {}

main() -> (.status_code: Int32) := {
    resource :: Resource = (.value = 1)
    pointer := &resource.value
    transition(.self = $$&resource)
    read(.value = pointer)
    status_code = 0
}
