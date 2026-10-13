Outcome: Type = (..yes, ..no)

Resource: Type = (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {

    }
)

Releaser: Abstract = (
    release(.self: &Self, .resource: $&Resource) -> (.first: Outcome, .second: Outcome) where {
        on first ..yes {
            on second ..yes { consumes(resource) }
        }
    }
)

Manager: Type = (.unused: Int32)

Manager implements Releaser

release(.self: &Manager, .resource: $&Resource) -> (.first: Outcome, .second: Outcome) := {
    first = ..yes
    second = ..yes
    deinit(resource)
}

main() -> () := {
    manager ::= Manager(0)
    releaser ::= to_virtual#(Releaser)(&manager)
}
