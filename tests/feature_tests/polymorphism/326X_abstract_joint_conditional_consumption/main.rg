Outcome: Type = (..yes, ..no)

Resource: Type = (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {

    }
)

Releaser#(.Participant: Type): Contract = (
    .release: (.self: &Participant, .resource: $&Resource) -> (.first: Outcome, .second: Outcome) where {
        on first ..yes {
            on second ..yes { consumes(resource) }
        }
    }
)

Manager: Type = (.unused: Int32)

implement Releaser#(Manager) (.release = _impl_release_Manager)

_impl_release_Manager := (.self: &Manager, .resource: $&Resource) -> (.first: Outcome, .second: Outcome)  {
    first = ..yes
    second = ..yes
    deinit(resource)
}

main() -> () := {
    manager ::= Manager(0)
    releaser ::= to_virtual#(Releaser)(&manager)
}
