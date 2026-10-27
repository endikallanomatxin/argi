Observer#(.Participant: Type): Contract = (
    .observe : (.self: &Participant, .first: $&Resource, .second: &Resource) -> (.result: Int32) where consumes(
        first
    )
)

Manager := (.unused: Int32 = 0)

Resource := (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {}
)

implement Observer#(Manager) (
    .observe = (.self: &Manager, .first: $&Resource, .second: &Resource) -> (.result: Int32) {
        deinit(.self = first)
        result = second&.value
    }
)

main := () -> (.status_code: Int32) {
    manager ::= Manager()
    first :: Resource = Resource(17)
    second :: Resource = Resource(42)
    status_code = observe(.self = &manager, .first = $&first, .second = &second)
}
