Resource : Type = (
    .value: Int32
)

mutate(.self: $&Resource) -> () := {
    self&.value = 2
}
read(.value: &Resource) -> () := {}

main() -> (.status_code: Int32) := {
    resource :: Resource = (.value = 1)
    pointer := &resource
    mutate(.self = $&resource)
    read(.value = pointer)
    status_code = 0
}
