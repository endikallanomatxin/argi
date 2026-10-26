Observer<.Participant: Type>: Contract = (
    .observe : (.self: &Participant, .first: $&Resource, .second: &Resource) -> (.result: Int32) where consumes(
        first
    )
)

Manager := (.unused: Int32 = 0)

Resource := (.value: Int32)

implement Deinit<Resource> (
    .deinit = (.self: $&Resource) -> () {}
)

implement Observer<Manager> (
    .observe = (.self: &Manager, .first: $&Resource, .second: &Resource) -> (.result: Int32) {
        deinit(.self = first)
        result = second&.value
    }
)

main := () -> () {
    manager ::= Manager()
    resource :: Resource = Resource(42)
    result ::= observe(.self = &manager, .first = $&resource, .second = &resource)
}
