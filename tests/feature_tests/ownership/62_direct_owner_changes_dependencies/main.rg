Resource : Type = (
    .value: Int32
)

Holder : Type = (
    .pointer: &Resource
)

main() -> (.status_code: Int32) := {
    first :: Resource = (.value = 1)
    second :: Resource = (.value = 2)
    holder :: Holder = (.pointer = &first)
    holder.pointer = &second
    status_code = 0
}
