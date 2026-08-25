Resource : Type = (
    .value: Int32
)

external_borrow(.value: &Resource) -> (.out: &Resource) : ExternFunction
deinit(.self: $&Resource) -> () #invalidates(self) := {}
read(.value: &Resource) -> () := {}

main() -> (.status_code: Int32) := {
    resource :: Resource = (.value = 1)
    pointer ::= external_borrow(.value = &resource)
    deinit(.self = $&resource)
    read(.value = pointer)
    status_code = 0
}
