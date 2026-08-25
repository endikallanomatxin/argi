Resource : Type = (
    .value: Int32
)

deinit(.self: $&Resource) -> () #invalidates(self) := {}
read(.value: &Resource) -> () := {}

main() -> (.status_code: Int32) := {
    resource :: Resource = (.value = 1)
    pointer := &resource
    running :: Bool = true
    while running {
        read(.value = pointer)
        deinit(.self = $&resource)
        running = false
    }
    status_code = 0
}
