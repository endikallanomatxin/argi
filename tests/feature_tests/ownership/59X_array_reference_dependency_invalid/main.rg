Resource : Type = (
    .value: Int32
)

deinit(.self: $&Resource) -> () #invalidates(self) := {}
read(.value: &Resource) -> () := {}

main() -> (.status_code: Int32) := {
    first :: Resource = (.value = 1)
    second :: Resource = (.value = 2)
    pointers :: [2]&Resource = (&first, &second)
    deinit(.self = $&first)
    read(.value = pointers[0])
    status_code = 0
}
