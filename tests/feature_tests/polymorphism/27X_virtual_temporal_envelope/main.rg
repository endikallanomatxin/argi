Readable : Abstract = ()

Resource : Type = (
    .value: Int32
)

Resource implements Readable

deinit(.self: $$&Resource) -> () #invalidates(self) := {}
read(.value: &Resource) -> () := {}

main() -> (.status_code: Int32) := {
    resource :: Resource = (.value = 42)
    erased ::= to_virtual#(.abstract: Readable)(.value = $&resource)
    pointer : $&Resource = cast#(.to: $&Resource)(.value = erased.data)
    deinit(.self = $$&resource)
    read(.value = pointer)
    status_code = 0
}
