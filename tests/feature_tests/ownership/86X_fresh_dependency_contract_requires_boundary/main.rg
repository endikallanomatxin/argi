Resource : Type = (
    .value: Int32
)

Holder : Type = (
    .pointer: &Resource
)

replace_with_fresh(.self: $$&Holder) -> () #sets_dependency_fresh(self, pointer) := {}

main() -> (.status_code: Int32) := {
    status_code = 0
}
