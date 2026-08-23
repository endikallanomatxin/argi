Resource : Type = (
    .value: Int32
)

external_reset(.self: $$&Resource) -> () : ExternFunction
read(.value: &Resource) -> () := {}

main() -> (.status_code: Int32) := {
    resource :: Resource = (.value = 1)
    pointer ::= &resource
    external_reset(.self = $$&resource)
    read(.value = pointer)
    status_code = 0
}
