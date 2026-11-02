Spec := (.name: StringView, .dependencies: ArrayView#(StringView))

implement ImplicitlyCopyable#(Spec) ()

Resource := (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {}
)

inspect := (.specs: ArrayView#(Spec)) -> (.found: Bool = false) {
    for spec in specs { if spec.name == "sample" { found = true } }
}

main := () -> (.status_code: Int32 = 1) {
    names: [1]StringView = ("other")
    specs: [1]Spec = ((.name = "sample", .dependencies = view(&names)))
    if inspect(.specs = view(&specs)).found == false { abort }
    values: [3]Int32 = (1, 2, 3)
    readonly ::= view(&values)
    total :: Int32 = 0
    for value in readonly { total = total + value }
    if total != 6 { abort }
    total = 0
    for &value in readonly { total = total + value&}
    if total != 6 { abort }
    writable ::= view($&values)
    for $&value in writable { value&= value&+ 1 }
    total = 0
    for value in writable { total = total + value }
    if total != 9 { abort }
    total = 0
    for &value in writable { total = total + value&}
    if total != 9 { abort }
    empty ::= empty_array_view#(Int32)()
    for value in empty { abort }
    resources: [1]Resource = ((.value = 42))
    resource_view ::= view(&resources)
    for &resource in resource_view { if resource&.value != 42 { abort } }
    mutable_resources ::= view($&resources)
    for $&resource in mutable_resources { resource&.value = 43 }
    for &resource in mutable_resources { if resource&.value != 43 { abort } }
    status_code = 0
}
